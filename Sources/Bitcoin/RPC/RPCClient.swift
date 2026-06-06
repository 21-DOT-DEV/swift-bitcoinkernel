//
//  RPCClient.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import bitcoind

let rpcLogger = Logger(subsystem: "Bitcoin", category: "RPC")

/// A client for interacting with the Bitcoin JSON-RPC API.
///
/// `RPCClient` provides a high-level interface for sending commands to a Bitcoin node
/// using the JSON-RPC protocol. It supports multiple transports: HTTP for remote nodes
/// and a direct in-process bridge for embedded daemons.
///
/// Transport selection can be explicit (via ``init(transport:)``) or automatic
/// (via ``init(url:username:password:)``), which picks the direct bridge when
/// available and falls back to HTTP.
///
/// RPC methods are organized into extensions matching
/// [Bitcoin Core's RPC categories](https://developer.bitcoin.org/reference/rpc/):
/// - `RPCClient+Blockchain.swift` — Blockchain RPCs (incl. mempool)
/// - `RPCClient+Control.swift` — Control RPCs
/// - `RPCClient+Generating.swift` — Generating RPCs
/// - `RPCClient+Mining.swift` — Mining RPCs
/// - `RPCClient+RawTransactions.swift` — Rawtransactions RPCs (incl. PSBT)
/// - `RPCClient+Util.swift` — Util RPCs
/// - `RPCClient+Network.swift` — Network RPCs
/// - `RPCClient+Wallet.swift` — Wallet RPCs
///
/// - Note: Targets Bitcoin Core v31.x. All RPCs are covered.
public final class RPCClient: Sendable {
    /// The transport used to send JSON-RPC requests.
    let transport: any RPCTransport

    /// Fresh decoder per call. Cost is negligible vs network I/O (~microseconds).
    /// Eliminates the data race risk of a shared `nonisolated(unsafe)` instance —
    /// no maintenance trap if someone later adds `dateDecodingStrategy` or similar.
    var decoder: JSONDecoder { JSONDecoder() }

    /// Initializes a new API client with an explicit transport.
    ///
    /// - Parameter transport: The transport to use for all RPC calls.
    public init(transport: any RPCTransport) {
        self.transport = transport
    }

    /// Initializes a new API client that auto-detects the best transport.
    ///
    /// Uses the direct in-process bridge when `bitcoin_rpc_ready()` returns 1,
    /// otherwise falls back to HTTP with explicit credentials. The decision is
    /// made per-call.
    ///
    /// ```swift
    /// let client = RPCClient(
    ///     url: URL(string: "http://127.0.0.1:18443")!,
    ///     username: "user",
    ///     password: "pass"
    /// )
    /// let info: BlockchainInfo = try await client.send("getblockchaininfo")
    /// ```
    ///
    /// - Parameters:
    ///   - url: The URL of the Bitcoin node's JSON-RPC endpoint.
    ///   - username: The username for HTTP authentication.
    ///   - password: The password for HTTP authentication.
    public init(url: URL, username: String, password: String) {
        self.transport = AutoTransport(
            http: HTTPTransport(url: url, username: username, password: password),
            direct: DirectTransport()
        )
    }

    /// Initializes a new API client using cookie-file authentication.
    ///
    /// Uses the direct in-process bridge when `bitcoin_rpc_ready()` returns 1,
    /// otherwise falls back to HTTP with credentials read from the `.cookie`
    /// file on each call. This is the preferred init for embedded daemons —
    /// no hardcoded credentials required.
    ///
    /// ```swift
    /// let client = RPCClient(
    ///     url: URL(string: "http://127.0.0.1:8332")!,
    ///     cookieFile: dataDir.appending(path: ".cookie")
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - url: The URL of the Bitcoin node's JSON-RPC endpoint.
    ///   - cookieFile: File URL to the `.cookie` file written by Bitcoin Core.
    public init(url: URL, cookieFile: URL) {
        self.transport = AutoTransport(
            http: CookieTransport(url: url, cookieFile: cookieFile),
            direct: DirectTransport()
        )
    }

    // MARK: - Generic Decode

    func decode<T: Decodable & Sendable>(_ data: Data, method: String) throws -> T {
        let response: JSONRPCResponse<T>
        do {
            response = try decoder.decode(JSONRPCResponse<T>.self, from: data)
        } catch {
            throw RPCClientError.decodingFailed(
                method: method, responseData: data, underlying: error)
        }
        if let error = response.error { throw error }
        guard let result = response.result else {
            throw RPCClientError.unexpectedNullResult(method: method, responseData: data)
        }
        return result
    }

    func decodeNullable<T: Decodable & Sendable>(_ data: Data, method: String) throws -> T? {
        let response: JSONRPCResponse<T>
        do {
            response = try decoder.decode(JSONRPCResponse<T>.self, from: data)
        } catch {
            throw RPCClientError.decodingFailed(
                method: method, responseData: data, underlying: error)
        }
        if let error = response.error { throw error }
        return response.result
    }

    // MARK: - Build Request

    func buildRequest(_ method: String, params: [RPCParam] = []) -> JSONRPCRequest {
        JSONRPCRequest(method: method, params: params)
    }

    // MARK: - Send Methods

    /// Sends an RPC and decodes the result into `T`.
    ///
    /// ```swift
    /// let count: Int = try await client.send("getblockcount")
    /// ```
    ///
    /// - Parameters:
    ///   - method: The RPC method name (e.g., `"getblockcount"`).
    ///   - params: The parameters to pass to the RPC method.
    /// - Returns: The decoded result.
    /// - Throws: ``RPCError`` (server), ``RPCClientError`` (client), or transport errors.
    public func send<T: Decodable & Sendable>(_ method: String, params: [RPCParam] = [])
        async throws -> T
    {
        let data = try await transport.send(buildRequest(method, params: params), path: nil)
        return try decode(data, method: method)
    }

    /// Sends an RPC and decodes the result into `T?`. Null is a valid domain value.
    ///
    /// Use for RPCs where `null` means something (e.g., `getTxOut` null = spent).
    ///
    /// - Parameters:
    ///   - method: The RPC method name.
    ///   - params: The parameters to pass to the RPC method.
    /// - Returns: The decoded result, or `nil` if the server returned null.
    /// - Throws: ``RPCError`` (server), ``RPCClientError`` (client), or transport errors.
    public func sendNullable<T: Decodable & Sendable>(_ method: String, params: [RPCParam] = [])
        async throws -> T?
    {
        let data = try await transport.send(buildRequest(method, params: params), path: nil)
        return try decodeNullable(data, method: method)
    }

    /// Sends an RPC expected to return null. If Bitcoin Core returns a non-null
    /// string, logs `.warning` — may indicate the RPC's semantics changed in a
    /// newer Core version. Fixture tests are the primary detection mechanism;
    /// this log is a secondary signal for runtime visibility.
    ///
    /// - Parameters:
    ///   - method: The RPC method name.
    ///   - params: The parameters to pass to the RPC method.
    /// - Throws: ``RPCError`` (server) or transport errors.
    public func sendVoid(_ method: String, params: [RPCParam] = []) async throws {
        let data = try await transport.send(buildRequest(method, params: params), path: nil)
        let response: JSONRPCResponse<String?>
        do {
            response = try decoder.decode(JSONRPCResponse<String?>.self, from: data)
        } catch {
            throw RPCClientError.decodingFailed(
                method: method, responseData: data, underlying: error)
        }
        if let error = response.error { throw error }
        if let value = response.result, let str = value, !str.isEmpty {
            rpcLogger.warning(
                "\(method): expected null, got '\(str)' — possible RPC semantics change")
        }
    }

    // MARK: - Wallet-scoped Send Methods

    /// Builds a percent-encoded wallet path for URL routing.
    private func walletPath(_ wallet: String) -> String {
        let encoded = wallet.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? wallet
        return "/wallet/\(encoded)"
    }

    /// Sends a wallet-scoped RPC and decodes the result into `T`.
    func send<T: Decodable & Sendable>(_ method: String, wallet: String, params: [RPCParam] = [])
        async throws -> T
    {
        let data = try await transport.send(
            buildRequest(method, params: params), path: walletPath(wallet))
        return try decode(data, method: method)
    }

    /// Sends a wallet-scoped RPC expected to return null.
    func sendVoid(_ method: String, wallet: String, params: [RPCParam] = []) async throws {
        let data = try await transport.send(
            buildRequest(method, params: params), path: walletPath(wallet))
        let response: JSONRPCResponse<String?>
        do {
            response = try decoder.decode(JSONRPCResponse<String?>.self, from: data)
        } catch {
            throw RPCClientError.decodingFailed(
                method: method, responseData: data, underlying: error)
        }
        if let error = response.error { throw error }
        if let value = response.result, let str = value, !str.isEmpty {
            rpcLogger.warning(
                "\(method): expected null, got '\(str)' — possible RPC semantics change")
        }
    }

    /// Sends a wallet-scoped RPC and returns raw response data.
    func callWallet(_ method: String, wallet: String, params: [RPCParam] = []) async throws -> Data
    {
        let data = try await transport.send(
            buildRequest(method, params: params), path: walletPath(wallet))
        try throwIfRPCError(data)
        return data
    }

    /// Returns raw JSON-RPC response data. Caller decodes as needed.
    ///
    /// Rare use case (<1% of calls) — typed methods cover ~94 RPCs.
    ///
    /// - Parameters:
    ///   - method: The RPC method name.
    ///   - params: The parameters to pass to the RPC method.
    /// - Returns: The raw response `Data`.
    /// - Throws: ``RPCError`` if the response contains a JSON-RPC error,
    ///   or transport errors.
    public func call(_ method: String, params: [RPCParam] = []) async throws -> Data {
        let data = try await transport.send(buildRequest(method, params: params), path: nil)
        try throwIfRPCError(data)
        return data
    }

    // MARK: - Private

    /// Checks raw response data for a JSON-RPC error and throws it if present.
    private func throwIfRPCError(_ data: Data) throws {
        struct ErrorEnvelope: Decodable { let error: RPCError? }
        if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data),
            let error = envelope.error
        {
            throw error
        }
    }
}
