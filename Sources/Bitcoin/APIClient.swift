//
//  APIClient.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2024 Timechain Software Initiative 
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import bitcoind

/// A client for interacting with the Bitcoin JSON-RPC API.
///
/// `APIClient` provides a high-level interface for sending commands to a Bitcoin node
/// using the JSON-RPC protocol. It supports multiple transports: HTTP for remote nodes
/// and a direct in-process bridge for embedded daemons.
///
/// Transport selection can be explicit (via ``init(transport:)``) or automatic
/// (via ``init(url:username:password:)``), which picks the direct bridge when
/// available and falls back to HTTP.
public class APIClient {
    /// The transport used to send JSON-RPC requests.
    private let transport: any RPCTransport

    /// Initializes a new API client with an explicit transport.
    ///
    /// - Parameter transport: The transport to use for all RPC calls.
    public init(transport: any RPCTransport) {
        self.transport = transport
    }

    /// Initializes a new API client that auto-detects the best transport.
    ///
    /// Uses the direct in-process bridge when `bitcoin_rpc_ready()` returns 1,
    /// otherwise falls back to HTTP. The decision is made per-call.
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

    /// Sends a command to the Bitcoin node and returns the decoded response.
    ///
    /// - Parameter command: The command to send, represented by a `Commands` enum value.
    /// - Parameter params: Optional parameters to pass with the command.
    /// - Returns: The decoded response of type `T`, which must conform to `Codable`.
    /// - Throws: An error if the request fails or if the response cannot be decoded.
    public func send<T: Codable>(_ command: Commands, params: [Any] = []) async throws -> T {
        let request = JSONRPCRequest(method: command.rawValue, params: params)
        let data = try await transport.send(request: request)
        return try Self.decode(data)
    }

    /// Decode raw JSON-RPC response data into the expected result type.
    static func decode<T: Codable>(_ data: Data) throws -> T {
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: data)

        if let error = response.error {
            throw NSError(
                domain: "JSONRPCError",
                code: error.code,
                userInfo: [NSLocalizedDescriptionKey: error.message]
            )
        }

        switch response.result {
        case .integer(let intValue):
            if T.self == Int.self { return intValue as! T }
        case .string(let stringValue):
            if T.self == String.self { return stringValue as! T }
        case .blockchainInfo(let blockchainInfo):
            if T.self == BlockchainInfo.self { return blockchainInfo as! T }
        case .blockWithTransactions(let blockWithTransactions):
            if T.self == BlockWithTransactions.self { return blockWithTransactions as! T }
        case .block(let block):
            if T.self == Block.self { return block as! T }
        case .null:
            if T.self == Void.self { return () as! T }
        }

        throw URLError(.cannotParseResponse)
    }

    /// Retrieves the current block count from the Bitcoin node.
    ///
    /// - Returns: An integer representing the current block count.
    /// - Throws: An error if the request fails or if the response cannot be decoded.
    public func getBlockCount() async throws -> Int {
        return try await send(.getBlockCount)
    }

    /// Retrieves a block from the Bitcoin node.
    ///
    /// - Parameters:
    ///   - hash: The hash of the block to retrieve.
    ///   - verbosity: The level of detail to retrieve for the block.
    /// - Returns: The block data, type depends on the verbosity level.
    /// - Throws: An error if the request fails or if the response cannot be decoded.
    public func getBlock(hash: String, verbosity: BlockVerbosity = .json) async throws -> Any {
        let params: [Any] = [hash, verbosity.rawValue]
        switch verbosity {
        case .raw:
            return try await send(.getBlock, params: params) as String
        case .json:
            return try await send(.getBlock, params: params) as Block
        case .jsonWithTransactions:
            return try await send(.getBlock, params: params) as BlockWithTransactions
        }
    }

    /// Requests a graceful shutdown of the Bitcoin node.
    ///
    /// - Returns: A string message from the server (e.g. "Bitcoin Core stopping").
    /// - Throws: An error if the request fails.
    public func stop() async throws -> String {
        return try await send(.stop)
    }

    /// Retrieves blockchain information from the Bitcoin node.
    ///
    /// - Returns: A `BlockchainInfo` instance representing the blockchain information.
    /// - Throws: An error if the request fails or if the response cannot be decoded.
    public func getBlockchainInfo() async throws -> BlockchainInfo {
        return try await send(.getBlockchainInfo)
    }
}
