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
/// using the JSON-RPC protocol. It abstracts away the details of constructing and
/// sending HTTP requests, allowing you to focus on the Bitcoin-specific operations.
///
/// - Important: This class assumes that `JSONRPCRequest`, `JSONRPCResponse`, `JSONRPCService`,
///   and related types are already defined elsewhere in the project.
public class APIClient {
    /// The underlying service used to send JSON-RPC requests.
    private let rpcService: JSONRPCService

    /// Initializes a new API client with the specified URL.
    ///
    /// - Parameter url: The URL of the Bitcoin node's JSON-RPC endpoint.
    ///   Defaults to `http://127.0.0.1:8332` if not provided.
    public init(url: URL, username: String, password: String) {
        self.rpcService = JSONRPCService(url: url, username: username, password: password)
    }

    /// Sends a command to the Bitcoin node and returns the decoded response.
    ///
    /// Automatically uses the in-process direct RPC bridge when available
    /// (after `_bridge_init` has been called), falling back to HTTP otherwise.
    ///
    /// - Parameter command: The command to send, represented by a `Commands` enum value.
    /// - Parameter params: Optional parameters to pass with the command.
    /// - Returns: The decoded response of type `T`, which must conform to `Codable`.
    /// - Throws: An error if the request fails or if the response cannot be decoded.
    public func send<T: Codable>(_ command: Commands, params: [Any] = []) async throws -> T {
        if bitcoin_rpc_ready() == 1 {
            return try directSend(command, params: params)
        }
        let request = JSONRPCRequest(method: command.rawValue, params: params)
        return try await rpcService.send(request: request)
    }

    /// Dispatch an RPC command directly against the in-process Bitcoin Core dispatch
    /// table, bypassing HTTP entirely. Returns the same decoded type as the HTTP path.
    private func directSend<T: Codable>(_ command: Commands, params: [Any] = []) throws -> T {
        let paramsData = try JSONSerialization.data(withJSONObject: params)
        let paramsJSON = String(data: paramsData, encoding: .utf8) ?? "[]"

        let resultPtr: UnsafeMutablePointer<CChar>? = command.rawValue.withCString { method in
            paramsJSON.withCString { params in
                bitcoin_rpc(method, params)
            }
        }

        guard let ptr = resultPtr else {
            throw URLError(.cannotConnectToHost)
        }
        defer { bitcoin_free(UnsafeMutableRawPointer(ptr)) }

        let data = Data(bytes: ptr, count: strlen(ptr))
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
