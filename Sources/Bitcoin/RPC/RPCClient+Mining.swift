//
//  RPCClient+Mining.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import RPCModels

// MARK: - Mining RPCs
// https://developer.bitcoin.org/reference/rpc/#mining-rpcs

extension RPCClient {

    /// Returns a block template for mining.
    ///
    /// - Parameter request: Template request parameters. The `rules` array is
    ///   required by Core v31.x — at minimum `["segwit"]`.
    public func getBlockTemplate(request: BlockTemplateRequest = BlockTemplateRequest()) async throws -> BlockTemplate {
        try await send("getblocktemplate", params: [.encodable(request)])
    }

    /// Returns mining-related information.
    public func getMiningInfo() async throws -> MiningInfo {
        try await send("getmininginfo")
    }

    /// Returns the estimated network hashes per second.
    ///
    /// - Parameters:
    ///   - nBlocks: The number of blocks to average over. Use -1 to average since last difficulty change.
    ///   - height: The block height to estimate at. Use -1 for current tip.
    public func getNetworkHashPS(nBlocks: Int = 120, height: Int = -1) async throws -> Double {
        try await send("getnetworkhashps", params: [.int(nBlocks), .int(height)])
    }

    /// Prioritises a transaction for mining by adjusting its fee delta.
    ///
    /// - Parameters:
    ///   - txid: The transaction id.
    ///   - feeDelta: The fee delta in satoshis to add (or subtract, if negative).
    /// - Returns: `true` on success.
    public func prioritiseTransaction(txid: String, feeDelta: Int64) async throws -> Bool {
        try await send("prioritisetransaction", params: [.string(txid), .int(0), .int64(feeDelta)])
    }

    /// Submits a block to the network.
    ///
    /// - Important: Not idempotent — a timeout does not mean the operation failed.
    ///   Do not retry automatically.
    ///
    /// - Parameter hexData: The hex-encoded block data to submit.
    /// - Throws: ``RPCClientError/blockRejected(reason:)`` if Core returns a rejection string.
    public func submitBlock(hexData: String) async throws {
        let data = try await transport.send(buildRequest("submitblock", params: [.string(hexData)]), path: nil)
        let response: JSONRPCResponse<String?>
        do {
            response = try decoder.decode(JSONRPCResponse<String?>.self, from: data)
        } catch {
            throw RPCClientError.decodingFailed(method: "submitblock", responseData: data, underlying: error)
        }
        if let error = response.error { throw error }
        if let value = response.result, let reason = value, !reason.isEmpty {
            throw RPCClientError.blockRejected(reason: reason)
        }
    }

    /// Submits a raw block header to the node.
    ///
    /// - Parameter hexData: The hex-encoded block header data.
    public func submitHeader(hexData: String) async throws {
        try await sendVoid("submitheader", params: [.string(hexData)])
    }

    /// Returns a map of all user-created fee deltas by txid (v27+).
    ///
    /// Shows transactions prioritised via `prioritisetransaction` and whether
    /// they are currently in the mempool.
    /// - Returns: Raw JSON mapping txid → `{fee_delta, in_mempool}`.
    public func getPrioritisedTransactions() async throws -> Data {
        try await call("getprioritisedtransactions")
    }
}
