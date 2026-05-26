//
//  JSONRPCService.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A service for sending JSON-RPC requests to a Bitcoin node over HTTP.
///
/// `JSONRPCService` delegates transport to ``HTTPTransport`` and decoding to
/// ``RPCClient``, providing a convenience wrapper for callers that
/// need direct access to the HTTP JSON-RPC layer.
public class JSONRPCService {
    /// The underlying API client.
    private let client: RPCClient

    /// Initializes a new JSON-RPC service with the specified URL, credentials, and session.
    ///
    /// - Parameters:
    ///   - url: The URL of the Bitcoin node's JSON-RPC endpoint.
    ///   - username: The username for authentication.
    ///   - password: The password for authentication.
    ///   - session: The URLSession to use for network requests. Defaults to `.shared`.
    public init(url: URL, username: String, password: String, session: URLSession = .shared) {
        self.client = RPCClient(
            transport: HTTPTransport(url: url, username: username, password: password, session: session)
        )
    }

    /// Sends an RPC method and returns the decoded response.
    ///
    /// - Parameters:
    ///   - method: The RPC method name.
    ///   - params: The parameters to pass.
    /// - Returns: The decoded response of type `T`.
    /// - Throws: An error if the request fails, the response is invalid, or decoding fails.
    public func send<T: Decodable & Sendable>(_ method: String, params: [RPCParam] = []) async throws -> T {
        try await client.send(method, params: params)
    }
}
