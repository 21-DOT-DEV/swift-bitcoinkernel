//
//  HTTPDataFetching.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The minimal HTTP capability ``EsploraBlockSource`` needs: fetch the bytes at
/// a URL.
///
/// `URLSession` conforms out of the box, so the common path is to pass a
/// `URLSession` — the default for
/// ``EsploraBlockSource/init(endpoint:urlSession:minimumInterRequestDelay:maximumRetries:baseRetryDelay:)``
/// is `URLSession.shared`. Inject a custom conformer to route requests through
/// an alternative HTTP stack, or — in tests — through a deterministic in-memory
/// double that performs no real networking. Tests use the latter so they never
/// touch `URLProtocol` global state or the network, which keeps them isolated,
/// parallel-safe, and immune to DNS-driven retry hangs.
public protocol HTTPDataFetching: Sendable {
    /// Fetch the contents of `url`, returning the body bytes and the response.
    func data(from url: URL) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPDataFetching {
    // Explicit witness rather than relying on the SDK's
    // `data(from:delegate:)` (whose defaulted delegate parameter differs by
    // platform) to satisfy the requirement. Routing through `data(for:)`
    // compiles uniformly on Apple and Linux's FoundationNetworking.
    public func data(from url: URL) async throws -> (Data, URLResponse) {
        try await data(for: URLRequest(url: url))
    }
}
