//
//  MockHTTPClient.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import BitcoinKernel
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Deterministic in-memory ``HTTPDataFetching`` double for tests.
///
/// Each instance owns its own response queue and request log, so nothing is
/// global: tests run in parallel with zero interference, never register a
/// `URLProtocol`, and never touch the network. A request with no queued
/// response returns a synthetic 500 immediately — it never blocks and never
/// escapes to DNS — so a retry loop can't hang. That last point is the whole
/// reason this replaced the old `URLProtocol`-based stub: when interception
/// silently failed, requests reached the real resolver against synthetic
/// hostnames, and `EsploraBlockSource` retried the (retryable) DNS failures
/// until the test timed out.
final class MockHTTPClient: HTTPDataFetching, @unchecked Sendable {
    /// A queued response the client returns for the next request.
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

    /// A record of a request the client handled.
    struct Record: Sendable {
        let url: URL
    }

    /// Synthetic base URL. Requests never leave the process, so the host is
    /// irrelevant; the `.invalid` TLD (RFC 6761) guarantees it can't resolve
    /// even if interception ever regressed.
    let baseURL = URL(string: "https://mock.invalid/api")!

    private let lock = NSLock()
    private var queue: [Response] = []
    private var _records: [Record] = []

    /// Enqueue a response. Responses are dequeued FIFO per request.
    func enqueue(_ response: Response) {
        lock.withLock { queue.append(response) }
    }

    /// Enqueue multiple responses in order.
    func enqueue(_ responses: [Response]) {
        lock.withLock { queue.append(contentsOf: responses) }
    }

    /// All requests the client has handled, in chronological order.
    var records: [Record] {
        lock.withLock { _records }
    }

    // MARK: - HTTPDataFetching

    func data(from url: URL) async throws -> (Data, URLResponse) {
        let response: Response = lock.withLock {
            _records.append(Record(url: url))
            if !queue.isEmpty {
                return queue.removeFirst()
            }
            // Queue exhausted: surface a 500 so an over-requesting test fails
            // fast (within the retry budget) instead of hanging.
            return Response(
                statusCode: 500,
                body: Data("MockHTTPClient: no response queued for \(url.path)".utf8),
                headers: [:]
            )
        }
        guard let http = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        ) else {
            throw URLError(.cannotParseResponse)
        }
        return (response.body, http)
    }
}
