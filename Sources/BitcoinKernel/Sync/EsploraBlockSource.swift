//
//  EsploraBlockSource.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A ``BlockSource`` backed by any Esplora-compatible HTTP endpoint —
/// mempool.space, blockstream.info, or a self-hosted Esplora instance.
///
/// - Important: No endpoint is hard-coded as a default. Callers MUST provide
///   one. The library ships convenience accessors for known public instances
///   (see `URL.mempoolSpaceSignet` et al.), but the choice of which network
///   to trust is an explicit caller decision — ``BitcoinKernel`` does not
///   silently pick a block explorer on behalf of the user.
///
/// ### Pacing, retry, and rate-limiting
///
/// - A per-instance `RequestPacer` actor ensures sequential requests stay
///   at least `minimumInterRequestDelay` apart (default: 100 ms).
/// - Failures with HTTP 5xx or 429 are retried up to `maximumRetries` times
///   with exponential backoff (base = `baseRetryDelay`, doubling each time,
///   capped at 2^6 × base).
/// - When the server sends a `Retry-After` header on a 429 or 5xx response,
///   the client honors it in preference to the exponential-backoff delay.
/// - Transient network errors (timeouts, DNS failures, connection drops)
///   are retried on the same policy.
/// - Other non-2xx responses (e.g., 400, 403) fail immediately with
///   ``BlockSourceError/invalidResponse(_:)``.
/// - 404 maps immediately to ``BlockSourceError/notFound`` without retry.
///
/// ### Hash orientation
///
/// `Data` hashes on this type are in internal (kernel) byte order, matching
/// the ``BlockSource`` contract. Translation to Esplora's display-hex format
/// happens inside the implementation at the HTTP boundary.
public struct EsploraBlockSource: BlockSource {
    private let endpoint: URL
    private let urlSession: URLSession
    private let pacer: RequestPacer
    private let maximumRetries: Int
    private let baseRetryDelay: Duration

    /// Create a new Esplora-backed block source.
    ///
    /// Each instance owns its own request pacer, so two sources pointing at
    /// different endpoints do not throttle each other. Reuse a single
    /// instance across your application when you want all requests to a
    /// given endpoint to share the pacing budget.
    ///
    /// - Parameters:
    ///   - endpoint: The Esplora API base URL — e.g.,
    ///     `URL.mempoolSpaceSignet`. No default is provided; the choice of
    ///     which network to trust is an explicit caller decision.
    ///   - urlSession: The `URLSession` used for HTTP requests. Defaults to
    ///     `.shared`. Pass a session with a SOCKS5-proxied configuration to
    ///     route sync through Tor.
    ///   - minimumInterRequestDelay: Minimum time between the start of
    ///     consecutive requests. Defaults to 100 ms, which keeps mempool.space
    ///     and blockstream.info well below their public rate limits.
    ///   - maximumRetries: Maximum retries after transient failures (HTTP
    ///     5xx, 429, retryable `URLError` codes). Defaults to 5. A value of
    ///     0 disables retries entirely — one attempt per request.
    ///   - baseRetryDelay: Starting backoff delay; doubles each retry up to
    ///     2^6 × base. Defaults to 500 ms, overridden by any
    ///     `Retry-After` header on 429 / 5xx responses.
    public init(
        endpoint: URL,
        urlSession: URLSession = .shared,
        minimumInterRequestDelay: Duration = .milliseconds(100),
        maximumRetries: Int = 5,
        baseRetryDelay: Duration = .milliseconds(500)
    ) {
        self.endpoint = endpoint
        self.urlSession = urlSession
        self.maximumRetries = maximumRetries
        self.baseRetryDelay = baseRetryDelay
        self.pacer = RequestPacer(minimumDelay: minimumInterRequestDelay)
    }

    // MARK: - BlockSource conformance

    public func bestTip() async throws -> BlockTip {
        let heightData = try await fetchData(url: EsploraAPI.tipHeightURL(base: endpoint))
        guard
            let heightString = String(data: heightData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            let height = Int(heightString)
        else {
            let raw = String(data: heightData, encoding: .utf8) ?? "<non-utf8>"
            throw BlockSourceError.invalidResponse("expected numeric tip height, got '\(raw)'")
        }

        let hashData = try await fetchData(url: EsploraAPI.tipHashURL(base: endpoint))
        guard
            let hashString = String(data: hashData, encoding: .utf8),
            let internalHash = EsploraAPI.internalHash(fromDisplayHex: hashString)
        else {
            let raw = String(data: hashData, encoding: .utf8) ?? "<non-utf8>"
            throw BlockSourceError.invalidResponse("expected 64-char hex tip hash, got '\(raw)'")
        }

        return BlockTip(hash: internalHash, height: height, timestamp: nil)
    }

    public func blockHash(atHeight height: Int) async throws -> Data {
        let data = try await fetchData(
            url: EsploraAPI.blockHashAtHeightURL(base: endpoint, height: height)
        )
        guard
            let string = String(data: data, encoding: .utf8),
            let internalHash = EsploraAPI.internalHash(fromDisplayHex: string)
        else {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw BlockSourceError.invalidResponse("expected 64-char hex hash, got '\(raw)'")
        }
        return internalHash
    }

    public func blockHeader(for hash: Data) async throws -> BlockHeader {
        let data = try await fetchData(
            url: EsploraAPI.blockHeaderURL(base: endpoint, hashInternal: hash)
        )
        guard
            let string = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            let rawHeader = EsploraAPI.data(fromHex: string),
            rawHeader.count == 80
        else {
            throw BlockSourceError.invalidResponse("expected 160 hex chars of header data")
        }
        do {
            return try BlockHeader(rawHeader)
        } catch {
            throw BlockSourceError.invalidResponse(
                "BlockHeader parse failed: \(error.localizedDescription)"
            )
        }
    }

    public func block(for hash: Data) async throws -> Block {
        let data = try await fetchData(
            url: EsploraAPI.blockRawURL(base: endpoint, hashInternal: hash)
        )
        do {
            return try Block(data)
        } catch {
            throw BlockSourceError.invalidResponse(
                "Block parse failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Paced + retrying fetch loop

    private func fetchData(url: URL) async throws -> Data {
        var attempt = 0
        while true {
            // Pacer reservation is atomic on the actor; sleep is outside the
            // actor so concurrent callers can sleep in parallel.
            let slot = await pacer.reserveNextSlot()
            try await Task.sleep(until: slot, clock: .continuous)

            do {
                let (data, response) = try await urlSession.data(from: url)

                guard let http = response as? HTTPURLResponse else {
                    throw BlockSourceError.invalidResponse("non-HTTP response")
                }

                if (200..<300).contains(http.statusCode) {
                    return data
                }
                if http.statusCode == 404 {
                    throw BlockSourceError.notFound
                }

                // Retryable: 429 / 5xx
                if http.statusCode == 429 || (500..<600).contains(http.statusCode) {
                    if attempt >= maximumRetries {
                        if http.statusCode == 429 {
                            throw BlockSourceError.rateLimited(
                                retryAfter: retryAfterDuration(from: http)
                            )
                        } else {
                            throw BlockSourceError.invalidResponse(
                                "HTTP \(http.statusCode) after \(attempt + 1) attempt(s)"
                            )
                        }
                    }
                    try await Task.sleep(for: retryDelay(for: http, attempt: attempt))
                    attempt += 1
                    continue
                }

                // Other non-2xx: fail immediately.
                throw BlockSourceError.invalidResponse("HTTP \(http.statusCode)")
            } catch let error as BlockSourceError {
                throw error
            } catch {
                // Transport-level error: retry if transient.
                if attempt < maximumRetries, isRetryableNetworkError(error) {
                    try await Task.sleep(for: retryDelay(for: nil, attempt: attempt))
                    attempt += 1
                    continue
                }
                throw BlockSourceError.network(underlying: error)
            }
        }
    }

    private func retryAfterDuration(from response: HTTPURLResponse) -> Duration? {
        guard
            let value = response.value(forHTTPHeaderField: "Retry-After"),
            let seconds = Double(value), seconds > 0
        else {
            return nil
        }
        return .seconds(seconds)
    }

    private func retryDelay(for response: HTTPURLResponse?, attempt: Int) -> Duration {
        if let response, let retryAfter = retryAfterDuration(from: response) {
            return retryAfter
        }
        let multiplier = 1 << min(attempt, 6)
        return baseRetryDelay * multiplier
    }

    private func isRetryableNetworkError(_ error: any Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .resourceUnavailable,
             .badURL, .secureConnectionFailed:
            // `.badURL` and `.secureConnectionFailed` are retryable here
            // because CFNetwork maps SOCKS5 proxy failures (e.g. a Tor
            // circuit dying after the system clock jumps) onto these codes
            // even when the URL itself is well-formed and TLS is fine.
            // Relevant to the Tor-routing path documented in `Sync.md`.
            return true
        default:
            return false
        }
    }
}
