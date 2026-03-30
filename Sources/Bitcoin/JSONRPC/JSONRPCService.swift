//
//  JSONRPCService.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2024 Timechain Software Initiative 
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// A service for sending JSON-RPC requests to a Bitcoin node over HTTP.
///
/// `JSONRPCService` delegates transport to ``HTTPTransport`` and decoding to
/// ``APIClient/decode(_:)``, providing a convenience wrapper for callers that
/// need direct access to the HTTP JSON-RPC layer.
public class JSONRPCService {
    /// The underlying HTTP transport.
    private let transport: HTTPTransport

    /// The coder used for encoding requests and decoding responses.
    public var coder: JSONRPCCoder

    /// Initializes a new JSON-RPC service with the specified URL, credentials, and session.
    ///
    /// - Parameters:
    ///   - url: The URL of the Bitcoin node's JSON-RPC endpoint.
    ///   - username: The username for authentication.
    ///   - password: The password for authentication.
    ///   - session: The URLSession to use for network requests. Defaults to `.shared`.
    public init(url: URL, username: String, password: String, session: URLSession = .shared) {
        self.transport = HTTPTransport(url: url, username: username, password: password, session: session)
        self.coder = JSONRPCCoder()
    }

    /// Sends a JSON-RPC request and returns the decoded response.
    ///
    /// - Parameter request: The JSON-RPC request to send.
    /// - Returns: The decoded response of type `T`, which must conform to `Codable`.
    /// - Throws: An error if the request fails, the response is invalid, or decoding fails.
    func send<T: Codable>(request: JSONRPCRequest) async throws -> T {
        let data = try await transport.send(request: request)
        return try APIClient.decode(data)
    }
}
