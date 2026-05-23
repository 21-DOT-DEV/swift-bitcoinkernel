//
//  HTTPTransport.swift
//  21-DOT-DEV/swift-bitcoin
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

/// Sends JSON-RPC requests over HTTP to a Bitcoin node.
///
/// Conforms to ``WalletCapableTransport`` — appends `/wallet/<name>` to the
/// base URL when `path` is non-nil.
public struct HTTPTransport: WalletCapableTransport {
    private let url: URL
    private let username: String
    private let password: String
    private let session: URLSession

    /// Creates an HTTP transport for a Bitcoin node's JSON-RPC endpoint.
    ///
    /// - Parameters:
    ///   - url: Base RPC URL (e.g., `http://127.0.0.1:8332`). Wallet path is appended per call.
    ///   - username: RPC username (from `rpcuser` or `rpcauth` in `bitcoin.conf`).
    ///   - password: RPC password (from `rpcpassword` or `rpcauth`).
    ///   - session: The `URLSession` used to dispatch requests. Defaults to `.shared`.
    public init(url: URL, username: String, password: String, session: URLSession = .shared) {
        self.url = url
        self.username = username
        self.password = password
        self.session = session
    }

    /// Sends a JSON-RPC request over HTTP with Basic authentication.
    ///
    /// When `path` is non-nil (e.g., `"/wallet/mywallet"`), it is appended to
    /// the base URL for wallet-scoped RPC calls. Returns HTTP 200 and 500
    /// responses (Bitcoin Core uses 500 for valid JSON-RPC errors); other
    /// status codes throw `URLError(.badServerResponse)`.
    public func send(_ request: JSONRPCRequest, path: String?) async throws -> Data {
        try Task.checkCancellation()

        var targetURL = url
        if let path {
            targetURL = url.appendingPathComponent(path)
        }

        var urlRequest = URLRequest(url: targetURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("text/plain", forHTTPHeaderField: "Content-Type")

        let requestData = try JSONEncoder().encode(request)
        urlRequest.httpBody = requestData

        let loginString = "\(username):\(password)"
        let loginData = loginString.data(using: .utf8)!
        let base64LoginString = loginData.base64EncodedString()
        urlRequest.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // Bitcoin Core returns HTTP 500 for valid JSON-RPC errors (e.g.,
        // "Method not found", invalid params, wallet not loaded). Pass these
        // through so RPCClient.decode() can extract the structured RPCError.
        if httpResponse.statusCode != 200 && httpResponse.statusCode != 500 {
            throw URLError(.badServerResponse)
        }

        return data
    }
}
