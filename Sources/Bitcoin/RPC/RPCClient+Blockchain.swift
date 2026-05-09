//
//  RPCClient+Blockchain.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import RPCModels

// MARK: - Blockchain RPCs
// https://developer.bitcoin.org/reference/rpc/#blockchain-rpcs

extension RPCClient {

    /// Retrieves the current block count.
    public func getBlockCount() async throws -> Int {
        try await send("getblockcount")
    }

    /// Retrieves blockchain information.
    public func getBlockchainInfo() async throws -> BlockchainInfo {
        try await send("getblockchaininfo")
    }

    /// Retrieves the hash of the best (tip) block.
    public func getBestBlockHash() async throws -> String {
        try await send("getbestblockhash")
    }

    // MARK: getBlock (typed variants)

    /// Returns a block with transaction IDs (verbosity 1, default).
    public func getBlock(hash: String) async throws -> Block {
        try await send("getblock", params: [.string(hash), .int(1)])
    }

    /// Returns a block with full transaction details (verbosity 2).
    public func getBlockVerbose(hash: String) async throws -> BlockWithTransactions {
        try await send("getblock", params: [.string(hash), .int(2)])
    }

    /// Returns a block with full transactions and prevout info (verbosity 3, v28+).
    public func getBlockPrevout(hash: String) async throws -> BlockWithPrevouts {
        try await send("getblock", params: [.string(hash), .int(3)])
    }

    /// Returns the hex-encoded serialized block data (verbosity 0).
    public func getBlockRaw(hash: String) async throws -> String {
        try await send("getblock", params: [.string(hash), .int(0)])
    }

    /// Returns hash of block at given height.
    public func getBlockHash(height: Int) async throws -> String {
        try await send("getblockhash", params: [.int(height)])
    }

    /// Returns a block header (verbose JSON).
    public func getBlockHeader(hash: String) async throws -> BlockHeader {
        try await send("getblockheader", params: [.string(hash), .bool(true)])
    }

    /// Returns a block header as hex string.
    public func getBlockHeaderRaw(hash: String) async throws -> String {
        try await send("getblockheader", params: [.string(hash), .bool(false)])
    }

    /// Returns the compact block filter for a block.
    public func getBlockFilter(hash: String, filterType: String = "basic") async throws -> BlockFilter {
        try await send("getblockfilter", params: [.string(hash), .string(filterType)])
    }

    /// Returns per-block statistics.
    ///
    /// - Parameters:
    ///   - hashOrHeight: Either a block hash (String) or height (Int) wrapped in `RPCParam`.
    ///   - stats: Optional array of stat names to return. If empty, returns all.
    public func getBlockStats(hashOrHeight: RPCParam, stats: [String]? = nil) async throws -> BlockStats {
        var params: [RPCParam] = [hashOrHeight]
        if let stats, !stats.isEmpty {
            params.append(.encodable(stats))
        }
        return try await send("getblockstats", params: params)
    }

    /// Returns information about all known chain tips.
    public func getChainTips() async throws -> [ChainTip] {
        try await send("getchaintips")
    }

    /// Returns statistics about the total number and rate of transactions.
    public func getChainTxStats(nBlocks: Int? = nil, hash: String? = nil) async throws -> ChainTxStats {
        var params: [RPCParam] = []
        if let nBlocks {
            params.append(.int(nBlocks))
            if let hash {
                params.append(.string(hash))
            }
        }
        return try await send("getchaintxstats", params: params)
    }

    /// Returns the proof-of-work difficulty as a multiple of the minimum difficulty.
    public func getDifficulty() async throws -> Double {
        try await send("getdifficulty")
    }

    /// Returns details about an unspent transaction output.
    ///
    /// Returns `nil` if the output has been spent.
    public func getTxOut(txid: String, vout: Int, includeMempool: Bool = true) async throws -> TxOut? {
        try await sendNullable("gettxout", params: [.string(txid), .int(vout), .bool(includeMempool)])
    }

    /// Returns a hex-encoded proof that one or more txids were included in a block.
    public func getTxOutProof(txids: [String], hash: String? = nil) async throws -> String {
        var params: [RPCParam] = [.encodable(txids)]
        if let hash {
            params.append(.string(hash))
        }
        return try await send("gettxoutproof", params: params)
    }

    /// Returns statistics about the UTXO set.
    public func getTxOutSetInfo(hashType: String? = nil, hash: String? = nil) async throws -> TxOutSetInfo {
        var params: [RPCParam] = []
        if let hashType {
            params.append(.string(hashType))
            if let hash {
                params.append(.string(hash))
            }
        }
        return try await send("gettxoutsetinfo", params: params)
    }

    /// Verifies a merkle proof and returns the txids it commits to.
    public func verifyTxOutProof(proof: String) async throws -> [String] {
        try await send("verifytxoutproof", params: [.string(proof)])
    }

    /// Treats a block as if it were received before others with the same work.
    public func preciousBlock(hash: String) async throws {
        try await sendVoid("preciousblock", params: [.string(hash)])
    }

    /// Prunes the blockchain up to `height`. Returns the last pruned block height.
    public func pruneBlockchain(height: Int) async throws -> Int {
        try await send("pruneblockchain", params: [.int(height)])
    }

    /// Dumps the mempool to disk.
    public func saveMempool() async throws {
        try await sendVoid("savemempool")
    }

    /// Scans the UTXO set for outputs matching the given descriptors.
    ///
    /// - Note: This can be a long-running operation. Consider increasing the timeout.
    public func scanTxOutSet(descriptors: [String]) async throws -> ScanTxOutResult {
        try await send("scantxoutset", params: [.string("start"), .encodable(descriptors)])
    }

    /// Aborts the current UTXO set scan.
    public func scanTxOutSetAbort() async throws -> Bool {
        try await send("scantxoutset", params: [.string("abort")])
    }

    /// Returns the progress of a running UTXO set scan, or `nil` if none is running.
    public func scanTxOutSetStatus() async throws -> ScanTxOutProgress? {
        try await sendNullable("scantxoutset", params: [.string("status")])
    }

    /// Verifies the blockchain database.
    public func verifyChain(checkLevel: Int = 3, nBlocks: Int = 6) async throws -> Bool {
        try await send("verifychain", params: [.int(checkLevel), .int(nBlocks)])
    }

    /// Returns deployment information (v24+).
    public func getDeploymentInfo(hash: String? = nil) async throws -> DeploymentInfo {
        var params: [RPCParam] = []
        if let hash {
            params.append(.string(hash))
        }
        return try await send("getdeploymentinfo", params: params)
    }

    /// Returns transaction spending prevout information (v24+).
    ///
    /// Each element is `{"txid": ..., "vout": ...}`.
    ///
    /// - Parameters:
    ///   - outputs: The prevouts to query `[{"txid": ..., "vout": ...}]`.
    ///   - mempoolOnly: Only check the mempool, not confirmed transactions (v31+).
    ///   - returnSpendingTx: Include the full spending transaction in the result (v31+).
    public func getTxSpendingPrevout(
        outputs: [[String: RPCParam]],
        mempoolOnly: Bool? = nil,
        returnSpendingTx: Bool? = nil
    ) async throws -> [TxSpendingPrevout] {
        var params: [RPCParam] = [.encodable(outputs)]
        if let mempoolOnly {
            params.append(.bool(mempoolOnly))
        } else if returnSpendingTx != nil {
            params.append(.null)
        }
        if let returnSpendingTx {
            params.append(.bool(returnSpendingTx))
        }
        return try await send("gettxspendingprevout", params: params)
    }

    // MARK: Mempool RPCs

    /// Returns details on the active state of the transaction memory pool.
    public func getMempoolInfo() async throws -> MempoolInfo {
        try await send("getmempoolinfo")
    }

    /// Returns all transaction ids in the memory pool.
    public func getRawMempool() async throws -> [String] {
        try await send("getrawmempool", params: [.bool(false)])
    }

    /// Returns all transactions in the memory pool with detailed information.
    public func getRawMempoolVerbose() async throws -> [String: MempoolEntry] {
        try await send("getrawmempool", params: [.bool(true)])
    }

    /// Returns mempool data for a given transaction.
    ///
    /// - Parameter txid: The transaction id (must be in mempool).
    public func getMempoolEntry(txid: String) async throws -> MempoolEntry {
        try await send("getmempoolentry", params: [.string(txid)])
    }

    /// Returns all in-mempool ancestors for a transaction (txid list).
    ///
    /// - Parameter txid: The transaction id (must be in mempool).
    public func getMempoolAncestors(txid: String) async throws -> [String] {
        try await send("getmempoolancestors", params: [.string(txid), .bool(false)])
    }

    /// Returns all in-mempool ancestors for a transaction with detailed information.
    ///
    /// - Parameter txid: The transaction id (must be in mempool).
    public func getMempoolAncestorsVerbose(txid: String) async throws -> [String: MempoolEntry] {
        try await send("getmempoolancestors", params: [.string(txid), .bool(true)])
    }

    /// Returns all in-mempool descendants for a transaction (txid list).
    ///
    /// - Parameter txid: The transaction id (must be in mempool).
    public func getMempoolDescendants(txid: String) async throws -> [String] {
        try await send("getmempooldescendants", params: [.string(txid), .bool(false)])
    }

    /// Returns all in-mempool descendants for a transaction with detailed information.
    ///
    /// - Parameter txid: The transaction id (must be in mempool).
    public func getMempoolDescendantsVerbose(txid: String) async throws -> [String: MempoolEntry] {
        try await send("getmempooldescendants", params: [.string(txid), .bool(true)])
    }

    /// Returns mempool cluster data for the cluster containing the given transaction (v31+).
    ///
    /// - Parameter txid: A transaction id in the cluster.
    /// - Returns: Raw JSON data for the cluster.
    public func getMempoolCluster(txid: String) async throws -> Data {
        try await call("getmempoolcluster", params: [.string(txid)])
    }

    /// Returns the feerate diagram for the entire mempool (v31+).
    public func getMempoolFeerateDiagram() async throws -> Data {
        try await call("getmempoolfeeratediagram")
    }

    /// Imports a mempool.dat file (v27+).
    ///
    /// - Parameter filePath: Path to the mempool.dat file.
    public func importMempool(filePath: String) async throws {
        try await sendVoid("importmempool", params: [.string(filePath)])
    }

    // MARK: Block management

    /// Waits for a new block and returns its hash and height.
    ///
    /// - Parameter timeout: Timeout in milliseconds (0 = no timeout, default 0).
    /// - Returns: Raw JSON with `hash` and `height`.
    public func waitForNewBlock(timeout: Int = 0) async throws -> Data {
        try await call("waitfornewblock", params: [.int(timeout)])
    }

    /// Waits until a specific block hash appears and returns its height.
    ///
    /// - Parameters:
    ///   - hash: The block hash to wait for.
    ///   - timeout: Timeout in milliseconds (0 = no timeout, default 0).
    /// - Returns: Raw JSON with `hash` and `height`.
    public func waitForBlock(hash: String, timeout: Int = 0) async throws -> Data {
        try await call("waitforblock", params: [.string(hash), .int(timeout)])
    }

    /// Waits until the blockchain reaches the specified height.
    ///
    /// - Parameters:
    ///   - height: The target block height.
    ///   - timeout: Timeout in milliseconds (0 = no timeout, default 0).
    /// - Returns: Raw JSON with `hash` and `height`.
    public func waitForBlockHeight(height: Int, timeout: Int = 0) async throws -> Data {
        try await call("waitforblockheight", params: [.int(height), .int(timeout)])
    }

    /// Permanently marks a block as invalid, as if it violated a consensus rule.
    ///
    /// - Parameter hash: The hash of the block to invalidate.
    public func invalidateBlock(hash: String) async throws {
        try await sendVoid("invalidateblock", params: [.string(hash)])
    }

    /// Removes invalidity status of a block and its descendants.
    ///
    /// - Parameter hash: The hash of the block to reconsider.
    public func reconsiderBlock(hash: String) async throws {
        try await sendVoid("reconsiderblock", params: [.string(hash)])
    }

    /// Attempts to fetch a block from a specific peer (v23+).
    ///
    /// - Parameters:
    ///   - hash: The block hash to fetch.
    ///   - peerId: The peer id to fetch from.
    public func getBlockFromPeer(hash: String, peerId: Int) async throws {
        try await sendVoid("getblockfrompeer", params: [.string(hash), .int(peerId)])
    }

    /// Scans blocks for matching descriptors using block filters (v24+).
    ///
    /// - Parameters:
    ///   - action: "start", "abort", or "status".
    ///   - descriptors: Descriptors to scan for (required for "start").
    ///   - startHeight: Start height (optional, default 0).
    ///   - stopHeight: Stop height (optional, default tip).
    ///   - filterType: Block filter type (default "basic").
    /// - Returns: Raw JSON with scan results.
    public func scanBlocks(
        action: String = "start",
        descriptors: [String]? = nil,
        startHeight: Int? = nil,
        stopHeight: Int? = nil,
        filterType: String = "basic"
    ) async throws -> Data {
        var params: [RPCParam] = [.string(action)]
        if let descriptors {
            params.append(.encodable(descriptors))
            params.append(startHeight.map { .int($0) } ?? .null)
            params.append(stopHeight.map { .int($0) } ?? .null)
            params.append(.string(filterType))
        }
        return try await call("scanblocks", params: params)
    }

    /// Returns activity for descriptors in a given block range (v31+).
    ///
    /// - Parameters:
    ///   - descriptors: Descriptors to check.
    ///   - blockHashes: Block hashes to scan (optional).
    /// - Returns: Raw JSON with descriptor activity.
    public func getDescriptorActivity(descriptors: [String], blockHashes: [String]? = nil) async throws -> Data {
        var params: [RPCParam] = [.encodable(descriptors)]
        if let blockHashes { params.append(.encodable(blockHashes)) }
        return try await call("getdescriptoractivity", params: params)
    }

    /// Dumps the UTXO set to a file (for AssumeUTXO snapshots).
    ///
    /// - Parameter filePath: The path to write the UTXO set dump.
    /// - Returns: Raw JSON with dump results.
    public func dumpTxOutSet(filePath: String) async throws -> Data {
        try await call("dumptxoutset", params: [.string(filePath)])
    }

    /// Loads a UTXO set snapshot from a file (for AssumeUTXO).
    ///
    /// - Parameter filePath: The path to the UTXO set file.
    /// - Returns: Raw JSON with load results.
    public func loadTxOutSet(filePath: String) async throws -> Data {
        try await call("loadtxoutset", params: [.string(filePath)])
    }

    /// Returns information about all active chainstates (v26+).
    public func getChainStates() async throws -> Data {
        try await call("getchainstates")
    }

    /// Waits for the validation interface queue to catch up (testing/debug).
    public func syncWithValidationInterfaceQueue() async throws {
        try await sendVoid("syncwithvalidationinterfacequeue")
    }
}
