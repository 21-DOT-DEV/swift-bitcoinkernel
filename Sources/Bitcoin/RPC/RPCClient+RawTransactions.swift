//
//  RPCClient+RawTransactions.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

// MARK: - Rawtransactions RPCs (includes PSBT)
// https://developer.bitcoin.org/reference/rpc/#rawtransactions-rpcs

extension RPCClient {

    // MARK: Raw Transaction

    /// Returns raw transaction data as hex string.
    ///
    /// - Parameters:
    ///   - txid: The transaction id.
    ///   - blockhash: The block hash to look in (optional, for pruned nodes).
    public func getRawTransaction(txid: String, blockhash: String? = nil) async throws -> String {
        var params: [RPCParam] = [.string(txid), .bool(false)]
        if let blockhash { params.append(.string(blockhash)) }
        return try await send("getrawtransaction", params: params)
    }

    /// Returns verbose transaction data.
    ///
    /// - Parameters:
    ///   - txid: The transaction id.
    ///   - blockhash: The block hash to look in (optional, for pruned nodes).
    public func getRawTransactionVerbose(txid: String, blockhash: String? = nil) async throws -> RawTransaction {
        var params: [RPCParam] = [.string(txid), .bool(true)]
        if let blockhash { params.append(.string(blockhash)) }
        return try await send("getrawtransaction", params: params)
    }

    /// Submits a raw transaction to the network.
    ///
    /// - Parameters:
    ///   - hex: The hex-encoded raw transaction.
    ///   - maxFeeRate: Maximum fee rate in BTC/kvB (default 0.10). Set to 0 to disable.
    ///   - maxBurnAmount: Maximum amount of BTC that can be sent to unspendable outputs (default 0).
    /// - Returns: The transaction hash (txid).
    public func sendRawTransaction(hex: String, maxFeeRate: Double = 0.10, maxBurnAmount: Double = 0) async throws -> String {
        try await send("sendrawtransaction", params: [.string(hex), .double(maxFeeRate), .double(maxBurnAmount)])
    }

    /// Submits a package of raw transactions to the network (v28+).
    ///
    /// - Parameters:
    ///   - rawTxs: Hex-encoded raw transactions. Parents must come before children.
    ///   - maxFeeRate: Maximum fee rate in BTC/kvB (default 0.10). Set to 0 to disable.
    ///   - maxBurnAmount: Maximum amount of BTC that can be sent to unspendable outputs (default 0).
    /// - Returns: Package acceptance results including individual tx results.
    public func submitPackage(rawTxs: [String], maxFeeRate: Double = 0.10, maxBurnAmount: Double = 0) async throws -> Data {
        try await call("submitpackage", params: [.encodable(rawTxs), .double(maxFeeRate), .double(maxBurnAmount)])
    }

    /// Returns information about transactions being privately broadcast (v31+).
    public func getPrivateBroadcastInfo() async throws -> Data {
        try await call("getprivatebroadcastinfo")
    }

    /// Aborts private broadcast for a transaction (v31+).
    ///
    /// - Parameter id: The transaction id to abort private broadcast for.
    public func abortPrivateBroadcast(id: String) async throws {
        try await sendVoid("abortprivatebroadcast", params: [.string(id)])
    }

    /// Creates a raw transaction (unsigned).
    ///
    /// - Parameters:
    ///   - inputs: Transaction inputs `[{"txid": ..., "vout": ...}]`.
    ///   - outputs: Transaction outputs `[{"address": amount}, ...]`.
    ///   - locktime: Raw locktime (default 0).
    ///   - replaceable: Opt into BIP 125 RBF (default false).
    /// - Returns: Hex-encoded raw transaction.
    public func createRawTransaction(
        inputs: [[String: RPCParam]],
        outputs: [[String: RPCParam]],
        locktime: Int = 0,
        replaceable: Bool = false
    ) async throws -> String {
        try await send("createrawtransaction", params: [
            .encodable(inputs), .encodable(outputs), .int(locktime), .bool(replaceable)
        ])
    }

    /// Decodes a hex-encoded raw transaction.
    public func decodeRawTransaction(hex: String) async throws -> DecodedTransaction {
        try await send("decoderawtransaction", params: [.string(hex)])
    }

    /// Combines multiple partially signed raw transactions into one.
    ///
    /// - Returns: Hex-encoded combined raw transaction.
    public func combineRawTransaction(hexes: [String]) async throws -> String {
        try await send("combinerawtransaction", params: [.encodable(hexes)])
    }

    /// Signs a raw transaction with private keys.
    ///
    /// - Parameters:
    ///   - hex: The hex-encoded raw transaction.
    ///   - privateKeys: Private keys in WIF format.
    ///   - prevTxs: Previous transaction outputs needed for signing.
    ///   - sigHashType: The signature hash type (default "DEFAULT" for taproot, "ALL" for legacy).
    public func signRawTransactionWithKey(
        hex: String,
        privateKeys: [String],
        prevTxs: [PrevTxOut] = [],
        sigHashType: String = "DEFAULT"
    ) async throws -> SignedTransaction {
        try await send("signrawtransactionwithkey", params: [
            .string(hex), .encodable(privateKeys), .encodable(prevTxs), .string(sigHashType)
        ])
    }

    /// Tests whether raw transactions would be accepted by mempool.
    ///
    /// - Parameters:
    ///   - rawTxs: Hex-encoded raw transactions to test.
    ///   - maxFeeRate: Maximum fee rate in BTC/kvB (default 0.10). Set to 0 to disable.
    public func testMempoolAccept(rawTxs: [String], maxFeeRate: Double = 0.10) async throws -> [MempoolAcceptResult] {
        try await send("testmempoolaccept", params: [.encodable(rawTxs), .double(maxFeeRate)])
    }

    /// Decodes a hex-encoded script.
    public func decodeScript(hex: String) async throws -> DecodedScript {
        try await send("decodescript", params: [.string(hex)])
    }

    /// Simulates the effect of raw transactions on the wallet (v22+).
    ///
    /// - Parameter rawTxs: Hex-encoded raw transactions.
    public func simulateRawTransaction(rawTxs: [String]) async throws -> SimulateRawTxResult {
        try await send("simulaterawtransaction", params: [.encodable(rawTxs)])
    }

    /// Creates a PSBT (unsigned) from inputs and outputs.
    ///
    /// - Parameters:
    ///   - inputs: Transaction inputs `[{"txid": ..., "vout": ...}]`.
    ///   - outputs: Transaction outputs `[{"address": amount}, ...]`.
    ///   - locktime: Raw locktime (default 0).
    ///   - replaceable: Opt into BIP 125 RBF (default false).
    /// - Returns: The PSBT base64 string.
    public func createPSBT(
        inputs: [[String: RPCParam]],
        outputs: [[String: RPCParam]],
        locktime: Int = 0,
        replaceable: Bool = false
    ) async throws -> String {
        try await send("createpsbt", params: [
            .encodable(inputs), .encodable(outputs), .int(locktime), .bool(replaceable)
        ])
    }

    // MARK: PSBT

    /// Decodes a PSBT (Partially Signed Bitcoin Transaction).
    ///
    /// - Parameter psbt: The PSBT base64 string.
    public func decodePSBT(psbt: String) async throws -> DecodedPSBT {
        try await send("decodepsbt", params: [.string(psbt)])
    }

    /// Analyzes a PSBT and provides information about its completion status.
    ///
    /// - Parameter psbt: The PSBT base64 string.
    public func analyzePSBT(psbt: String) async throws -> PSBTAnalysis {
        try await send("analyzepsbt", params: [.string(psbt)])
    }

    /// Combines multiple PSBTs into one.
    ///
    /// - Returns: The combined PSBT base64 string.
    public func combinePSBT(psbts: [String]) async throws -> String {
        try await send("combinepsbt", params: [.encodable(psbts)])
    }

    /// Converts a raw transaction to a PSBT.
    ///
    /// - Parameters:
    ///   - hex: The hex-encoded raw transaction.
    ///   - permitSigData: Allow conversion of signed inputs (default false).
    /// - Returns: The PSBT base64 string.
    public func convertToPSBT(hex: String, permitSigData: Bool = false) async throws -> String {
        try await send("converttopsbt", params: [.string(hex), .bool(permitSigData)])
    }

    /// Finalizes a PSBT.
    ///
    /// - Parameters:
    ///   - psbt: The PSBT base64 string.
    ///   - extract: Extract and return the network transaction if complete (default true).
    public func finalizePSBT(psbt: String, extract: Bool = true) async throws -> FinalizedPSBT {
        try await send("finalizepsbt", params: [.string(psbt), .bool(extract)])
    }

    /// Joins multiple PSBTs (for CoinJoin workflows).
    ///
    /// - Returns: The joined PSBT base64 string.
    public func joinPSBTs(psbts: [String]) async throws -> String {
        try await send("joinpsbts", params: [.encodable(psbts)])
    }

    /// Updates a PSBT with UTXO data from the UTXO set.
    ///
    /// - Parameters:
    ///   - psbt: The PSBT base64 string.
    ///   - descriptors: Descriptors to add to the PSBT (optional).
    /// - Returns: The updated PSBT base64 string.
    public func utxoUpdatePSBT(psbt: String, descriptors: [String]? = nil) async throws -> String {
        var params: [RPCParam] = [.string(psbt)]
        if let descriptors { params.append(.encodable(descriptors)) }
        return try await send("utxoupdatepsbt", params: params)
    }
}
