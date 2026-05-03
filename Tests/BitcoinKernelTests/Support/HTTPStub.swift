import Foundation

/// Test harness that intercepts HTTP requests via `URLProtocol` and replays
/// queued mock responses. Designed for per-test isolation: each ``HTTPStub``
/// instance owns its own response queue and request records, so tests can run
/// in parallel without state bleed.
///
/// ### Usage
///
/// ```swift
/// let stub = HTTPStub()
/// stub.enqueue(.ok(body: "800000"))
/// stub.enqueue(.ok(body: "00000000..."))
///
/// let session = stub.makeSession()
/// let source = EsploraBlockSource(endpoint: stub.baseURL, urlSession: session)
/// let tip = try await source.bestTip()
///
/// #expect(stub.records.count == 2)
/// ```
///
/// Isolation mechanism: each stub has a unique UUID. The session it returns
/// injects that UUID as an `X-HTTPStub-ID` header on every request. The
/// ``HTTPStubProtocol`` subclass reads that header and looks up the
/// corresponding stub instance via a thread-safe registry.
final class HTTPStub: @unchecked Sendable {
    /// A queued or default response the stub will return for the next request.
    struct Response: Sendable {
        var statusCode: Int
        var body: Data
        var headers: [String: String]

        /// 200 OK with a plain-text body (UTF-8 encoded).
        static func ok(body: String, headers: [String: String] = [:]) -> Response {
            Response(statusCode: 200, body: Data(body.utf8), headers: headers)
        }

        /// 200 OK with a raw binary body.
        static func ok(data: Data, headers: [String: String] = [:]) -> Response {
            Response(statusCode: 200, body: data, headers: headers)
        }

        /// 404 Not Found.
        static func notFound() -> Response {
            Response(statusCode: 404, body: Data(), headers: [:])
        }

        /// 429 Too Many Requests with a numeric `Retry-After` hint (seconds).
        static func rateLimited(retryAfterSeconds: Int) -> Response {
            Response(
                statusCode: 429,
                body: Data(),
                headers: ["Retry-After": String(retryAfterSeconds)]
            )
        }

        /// 5xx server error with an optional body.
        static func serverError(code: Int = 500, body: String = "") -> Response {
            Response(statusCode: code, body: Data(body.utf8), headers: [:])
        }
    }

    /// A record of a request the stub handled — URL, method, and a
    /// monotonic clock timestamp at which ``HTTPStubProtocol`` began loading.
    struct Record: Sendable {
        let url: URL
        let method: String
        let startedAt: ContinuousClock.Instant
    }

    /// Unique identifier for this stub; embedded in session headers for routing.
    let id: UUID

    /// A synthetic base URL pointing at an unroutable domain — all requests
    /// are intercepted, so the host is irrelevant, but a distinct hostname
    /// per stub aids debugging.
    let baseURL: URL

    private let lock = NSLock()
    private var queue: [Response] = []
    private var _defaultResponse: Response?
    private var _records: [Record] = []

    init() {
        let id = UUID()
        self.id = id
        // Use a `.test` TLD (RFC 6761 reserved) so there's zero risk of
        // accidentally hitting a real host if interception ever fails.
        self.baseURL = URL(string: "https://\(id.uuidString.lowercased()).test/api")!
        Self.register(self)
    }

    deinit {
        Self.unregister(id: self.id)
    }

    /// Enqueue a response. Responses are dequeued FIFO per request.
    func enqueue(_ response: Response) {
        lock.withLock { queue.append(response) }
    }

    /// Enqueue multiple responses in order.
    func enqueue(_ responses: [Response]) {
        lock.withLock { queue.append(contentsOf: responses) }
    }

    /// Set a default response returned when the queue is empty. Without a
    /// default, an empty queue surfaces a 500 error (flags bugs in tests
    /// that issue more requests than expected).
    func setDefault(_ response: Response) {
        lock.withLock { _defaultResponse = response }
    }

    /// All requests the stub has handled, in chronological order.
    var records: [Record] {
        lock.withLock { _records }
    }

    /// Number of responses still queued.
    var queuedCount: Int {
        lock.withLock { queue.count }
    }

    /// Build a `URLSession` that routes all requests through this stub.
    func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HTTPStubProtocol.self] + (config.protocolClasses ?? [])
        config.httpAdditionalHeaders = ["X-HTTPStub-ID": id.uuidString]
        // Avoid cached responses across tests.
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }

    // MARK: URLProtocol-side API (fileprivate).

    fileprivate func consumeNextResponse(for request: URLRequest) -> Response {
        let url = request.url ?? URL(string: "about:blank")!
        let method = request.httpMethod ?? "GET"
        let record = Record(url: url, method: method, startedAt: .now)
        return lock.withLock {
            _records.append(record)
            if !queue.isEmpty {
                return queue.removeFirst()
            }
            if let d = _defaultResponse {
                return d
            }
            return Response(
                statusCode: 500,
                body: Data("HTTPStub: no mock response queued for \(url.path)".utf8),
                headers: ["Content-Type": "text/plain; charset=utf-8"]
            )
        }
    }

    // MARK: Registry (for URLProtocol subclass to find the stub by header ID).

    nonisolated(unsafe) private static var registry: [UUID: HTTPStub] = [:]
    private static let registryLock = NSLock()

    private static func register(_ stub: HTTPStub) {
        registryLock.withLock { registry[stub.id] = stub }
    }

    private static func unregister(id: UUID) {
        _ = registryLock.withLock { registry.removeValue(forKey: id) }
    }

    fileprivate static func lookup(id: UUID) -> HTTPStub? {
        registryLock.withLock { registry[id] }
    }
}

/// `URLProtocol` subclass installed on ``HTTPStub``'s session. Routes every
/// request to the matching stub instance (identified by the `X-HTTPStub-ID`
/// request header) and replays its next queued response.
final class HTTPStubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: "X-HTTPStub-ID") != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard
            let idString = request.value(forHTTPHeaderField: "X-HTTPStub-ID"),
            let id = UUID(uuidString: idString),
            let stub = HTTPStub.lookup(id: id),
            let url = request.url
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let response = stub.consumeNextResponse(for: request)

        guard let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotParseResponse))
            return
        }

        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
