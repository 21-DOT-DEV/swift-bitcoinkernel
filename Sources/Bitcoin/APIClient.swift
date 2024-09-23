//
//  APIClient.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// A client for interacting with a Bitcoin node via JSON-RPC.
public class APIClient {
    private let rpcService: RPCService

    public init(config: BitcoinNodeConfig) {
        self.rpcService = RPCService(config: config)
    }

    /// Executes a Bitcoin JSON-RPC command.
    /// - Parameters:
    ///   - command: The command to execute.
    ///   - params: Optional parameters for the command.
    /// - Returns: The decoded response from the Bitcoin node.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func command<T: Codable>(_ command: Commands, params: [Codable] = []) async throws -> T {
        let anyCodableParams = params.map { AnyCodable($0) }
        let request = JSONRPCRequest(jsonrpc: "1.0", method: command.rawValue, params: anyCodableParams, id: 1)
        return try await rpcService.send(request: request)
    }

    // Convenience methods for common operations
    public func getBlockCount() async throws -> Int {
        return try await command(.getBlockCount)
    }

    public func sendToAddress(address: String, amount: Double) async throws -> String {
        return try await command(.sendToAddress, params: [address, amount])
    }

    /// Get the hash of the best (tip) block in the most-work fully-validated chain.
    /// - Returns: The block hash, hex-encoded.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func getBestBlockHash() async throws -> BlockHash {
        return try await command(.getBestBlockHash)
    }

    // Add more convenience methods as needed
}

extension APIClient {
    /// Get block information by block hash.
    /// - Parameters:
    ///   - blockhash: The block hash.
    ///   - verbosity: The verbosity of the result. 0 for hex-encoded data, 1 for a json object, and 2 for json object with transaction data. Default is 1.
    /// - Returns: Block information.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func getBlock(blockhash: String, verbosity: Int = 1) async throws -> Block {
        return try await command(.getBlock, params: [blockhash, verbosity])
    }

    /// Retrieve a BIP 157 content filter for a particular block.
    /// - Parameters:
    ///   - blockhash: The hash of the block.
    ///   - filtertype: The type name of the filter. Default is "basic".
    /// - Returns: The block filter information.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func getBlockFilter(blockhash: String, filtertype: String = "basic") async throws -> BlockFilter {
        return try await command(.getBlockFilter, params: [blockhash, filtertype])
    }

    /// Returns hash of block in best-block-chain at the provided height.
    /// - Parameter height: The height index.
    /// - Returns: The block hash.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func getBlockHash(height: Int) async throws -> String {
        return try await command(.getBlockHash, params: [height])
    }

    /// Get block header information by block hash.
    /// - Parameters:
    ///   - blockhash: The block hash.
    ///   - verbose: If true, return a JSON object, if false, return the hex-encoded data. Default is true.
    /// - Returns: Block header information if verbose is true, or hex-encoded data if verbose is false.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func getBlockHeader(blockhash: String, verbose: Bool = true) async throws -> BlockHeader {
        if verbose {
            return try await command(.getBlockHeader, params: [blockhash, verbose])
        } else {
            let hexString: String = try await command(.getBlockHeader, params: [blockhash, verbose])
            return BlockHeader(hash: hexString, confirmations: 0, height: 0, version: 0, versionHex: "", merkleroot: "", time: 0, mediantime: 0, nonce: 0, bits: "", difficulty: 0, chainwork: "", nTx: 0, previousblockhash: nil, nextblockhash: nil)
        }
    }

    /// Compute per block statistics for a given window.
    /// - Parameters:
    ///   - hashOrHeight: The block hash or height of the target block.
    ///   - stats: Optional array of statistics to retrieve. If nil, all statistics are retrieved.
    /// - Returns: Block statistics.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func getBlockStats(hashOrHeight: String, stats: [String]? = nil) async throws -> BlockStats {
        if let stats = stats {
            return try await command(.getBlockStats, params: [hashOrHeight, stats])
        } else {
            return try await command(.getBlockStats, params: [hashOrHeight])
        }
    }

    /// Return information about all known tips in the block tree, including the main chain as well as orphaned branches.
    /// - Returns: An array of chain tips.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func getChainTips() async throws -> [ChainTip] {
        return try await command(.getChainTips)
    }

    /// Compute statistics about the total number and rate of transactions in the chain.
    /// - Parameters:
    ///   - nblocks: Size of the window in number of blocks. Default is one month.
    ///   - blockhash: The hash of the block that ends the window. Default is the chain tip.
    /// - Returns: Chain transaction statistics.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func getChainTxStats(nblocks: Int? = nil, blockhash: String? = nil) async throws -> ChainTxStats {
        var params: [Codable] = []
        if let nblocks = nblocks {
            params.append(nblocks)
        }
        if let blockhash = blockhash {
            params.append(blockhash)
        }
        return try await command(.getChainTxStats, params: params)
    }

    /// Returns the proof-of-work difficulty as a multiple of the minimum difficulty.
    /// - Returns: The difficulty as a Double.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network issues.
    public func getDifficulty() async throws -> Double {
        return try await command(.getDifficulty)
    }

    /// If txid is in the mempool, returns all in-mempool ancestors.
    /// - Parameters:
    ///   - txid: The transaction id (must be in mempool)
    ///   - verbose: True for a json object, false for array of transaction ids. Default is false.
    /// - Returns: Array of transaction ids if verbose is false, or dictionary of MempoolEntry objects if verbose is true.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func getMempoolAncestors(txid: String, verbose: Bool = false) async throws -> Any {
        let result: Any = try await command(.getMempoolAncestors, params: [txid, verbose])
        if verbose {
            if let dict = result as? [String: [String: Any]] {
                return try JSONDecoder().decode([String: MempoolEntry].self, from: JSONSerialization.data(withJSONObject: dict))
            } else {
                throw JSONRPCError(code: -32603, message: "Unexpected response format")
            }
        } else {
            return result
        }
    }

    /// If txid is in the mempool, returns all in-mempool descendants.
    /// - Parameters:
    ///   - txid: The transaction id (must be in mempool)
    ///   - verbose: True for a json object, false for array of transaction ids. Default is false.
    /// - Returns: Array of transaction ids if verbose is false, or dictionary of MempoolEntry objects if verbose is true.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func getMempoolDescendants(txid: String, verbose: Bool = false) async throws -> Any {
        let result: Any = try await command(.getMempoolDescendants, params: [txid, verbose])
        if verbose {
            if let dict = result as? [String: [String: Any]] {
                return try JSONDecoder().decode([String: MempoolEntry].self, from: JSONSerialization.data(withJSONObject: dict))
            } else {
                throw JSONRPCError(code: -32603, message: "Unexpected response format")
            }
        } else {
            return result
        }
    }

    /// Returns mempool data for a given transaction.
    /// - Parameter txid: The transaction id (must be in mempool)
    /// - Returns: Mempool entry data for the specified transaction.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func getMempoolEntry(txid: String) async throws -> MempoolEntry {
        return try await command(.getMempoolEntry, params: [txid])
    }

    /// Returns details on the active state of the TX memory pool.
    /// - Returns: Mempool information.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func getMempoolInfo() async throws -> MempoolInfo {
        return try await command(.getMempoolInfo)
    }

    /// Returns all transaction ids in memory pool as a json array of string transaction ids.
    /// - Parameters:
    ///   - verbose: True for a json object, false for array of transaction ids. Default is false.
    ///   - mempool_sequence: If verbose=false, returns a json object with transaction list and mempool sequence number attached. Default is false.
    /// - Returns: Raw mempool data.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func getRawMempool(verbose: Bool = false, mempool_sequence: Bool = false) async throws -> RawMempool {
        let result: Any = try await command(.getRawMempool, params: [verbose, mempool_sequence])
        
        if verbose {
            if let transactions = result as? [String: [String: Any]] {
                let mempoolEntries = try JSONDecoder().decode([String: MempoolEntry].self, from: JSONSerialization.data(withJSONObject: transactions))
                return RawMempool(transactions: mempoolEntries)
            }
        } else if mempool_sequence {
            if let dict = result as? [String: Any],
               let txids = dict["txids"] as? [String],
               let sequence = dict["mempool_sequence"] as? Int {
                return RawMempool(txids: txids, mempool_sequence: sequence)
            }
        } else {
            if let txids = result as? [String] {
                return RawMempool(txids: txids)
            }
        }
        
        throw JSONRPCError(code: -32603, message: "Unexpected response format")
    }
}

extension APIClient {
    /// Returns details about an unspent transaction output.
    /// - Parameters:
    ///   - txid: The transaction id
    ///   - n: vout number
    ///   - include_mempool: Whether to include the mempool. Default is true.
    /// - Returns: Details about the unspent transaction output, or nil if not found.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func getTxOut(txid: String, n: Int, include_mempool: Bool = true) async throws -> TxOut? {
        let result: TxOut? = try await command(.getTxOut, params: [txid, n, include_mempool])
        return result
    }
}

extension APIClient {
    /// Returns a hex-encoded proof that "txid" was included in a block.
    /// - Parameters:
    ///   - txids: An array of transaction ids to filter
    ///   - blockhash: If specified, looks for txid in the block with this hash
    /// - Returns: A string that is a serialized, hex-encoded data for the proof.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func getTxOutProof(txids: [String], blockhash: String? = nil) async throws -> String {
        var params: [Codable] = [txids]
        if let blockhash = blockhash {
            params.append(blockhash)
        }
        return try await command(.getTxOutProof, params: params)
    }
}

extension APIClient {
    /// Treats a block as if it were received before others with the same work.
    /// - Parameter blockhash: The hash of the block to mark as precious
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network issues.
    public func preciousBlock(blockhash: String) async throws {
        try await command(.preciousBlock, params: [blockhash])
    }
}

extension APIClient {
    /// Dumps the mempool to disk.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network issues.
    public func saveMempool() async throws {
        try await command(.saveMempool)
    }
}

extension APIClient {
    /// Returns statistics about the unspent transaction output set.
    /// - Parameter hash_type: Which UTXO set hash should be calculated. Options: 'hash_serialized_2' (the legacy algorithm), 'none'.
    /// - Returns: UTXO set information.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func getTxOutSetInfo(hash_type: String = "hash_serialized_2") async throws -> UTXOSetInfo {
        return try await command(.getTxOutSetInfo, params: [hash_type])
    }
}

extension APIClient {
    /// Scans the unspent transaction output set for entries that match certain output descriptors.
    /// - Parameters:
    ///   - action: The action to execute. "start" for starting a scan, "abort" for aborting the current scan, "status" for progress report of the current scan.
    ///   - scanObjects: Array of scan objects. Required for "start" action. Each scan object is either a string descriptor or an object with descriptor and metadata.
    /// - Returns: Scan result.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func scanTxOutSet(action: String, scanObjects: [Any]? = nil) async throws -> ScanTxOutSetResult {
        var params: [Codable] = [action]
        if let scanObjects = scanObjects {
            params.append(scanObjects)
        }
        return try await command(.scanTxOutSet, params: params)
    }
}

extension APIClient {
    /// Returns details about an unspent transaction output.
    /// - Parameters:
    ///   - txid: The transaction id
    ///   - n: vout number
    ///   - include_mempool: Whether to include the mempool. Default is true.
    /// - Returns: Details about the unspent transaction output, or nil if not found.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func getTxOut(txid: String, n: Int, include_mempool: Bool = true) async throws -> TxOut? {
        let result: TxOut? = try await command(.getTxOut, params: [txid, n, include_mempool])
        return result
    }
}

extension APIClient {
    /// Returns details about the RPC server.
    /// - Returns: Information about active RPC commands and the debug log path.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func getRPCInfo() async throws -> RPCInfo {
        return try await command(.getRPCInfo)
    }
}

extension APIClient {
    /// List all commands, or get help for a specified command.
    /// - Parameter command: The command to get help on. If nil, lists all commands.
    /// - Returns: The help text.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func help(command: String? = nil) async throws -> String {
        if let command = command {
            return try await self.command(.help, params: [command])
        } else {
            return try await self.command(.help)
        }
    }
}

extension APIClient {
    /// Mine a block with a set of ordered transactions immediately to a specified address or descriptor.
    /// - Parameters:
    ///   - output: The address or descriptor to send the newly generated bitcoin to.
    ///   - transactions: An array of hex strings which are either txids or raw transactions.
    /// - Returns: The hash of the generated block.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func generateBlock(output: String, transactions: [String]) async throws -> GenerateBlockResult {
        return try await command(.generateBlock, params: [output, transactions])
    }
}

extension APIClient {
    /// Attempts to add or remove a node from the addnode list, or try a connection to a node once.
    /// - Parameters:
    ///   - node: The node (see getpeerinfo for nodes)
    ///   - command: 'add' to add a node to the list, 'remove' to remove a node from the list, 'onetry' to try a connection to the node once
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func addNode(node: String, command: String) async throws {
        try await self.command(.addNode, params: [node, command])
    }
}

extension APIClient {
    /// Immediately disconnects from the specified peer node.
    /// - Parameters:
    ///   - address: The IP address/port of the node. Optional if nodeid is provided.
    ///   - nodeid: The node ID (see getpeerinfo for node IDs). Optional if address is provided.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func disconnectNode(address: String? = nil, nodeid: Int? = nil) async throws {
        guard address != nil || nodeid != nil else {
            throw BitcoinError.invalidParameter("Either address or nodeid must be provided")
        }
        
        var params: [Codable] = []
        if let address = address {
            params.append(address)
        } else {
            params.append("")
        }
        if let nodeid = nodeid {
            params.append(nodeid)
        }
        
        try await command(.disconnectNode, params: params)
    }
}

extension APIClient {
    /// Combine multiple partially signed Bitcoin transactions into one transaction.
    /// - Parameter psbts: An array of base64 strings of partially signed transactions.
    /// - Returns: The base64-encoded combined partially signed transaction.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func combinePSBT(_ psbts: [String]) async throws -> String {
        return try await command(.combinePSBT, params: [psbts])
    }
}

extension APIClient {
    /// Get raw transaction data.
    /// - Parameters:
    ///   - txid: The transaction id.
    ///   - verbose: If false, return a string, otherwise return a json object. Default is false.
    ///   - blockhash: The block in which to look for the transaction.
    /// - Returns: The raw transaction data as a string if verbose is false, or a `DecodedRawTransaction` object if verbose is true.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func getRawTransaction(txid: String, verbose: Bool = false, blockhash: String? = nil) async throws -> Any {
        var params: [Codable] = [txid, verbose]
        if let blockhash = blockhash {
            params.append(blockhash)
        }
        
        let result: Any = try await command(.getRawTransaction, params: params)
        
        if verbose {
            if let dict = result as? [String: Any] {
                return try JSONDecoder().decode(DecodedRawTransaction.self, from: JSONSerialization.data(withJSONObject: dict))
            } else {
                throw JSONRPCError(code: -32603, message: "Unexpected response format")
            }
        } else {
            if let hexString = result as? String {
                return hexString
            } else {
                throw JSONRPCError(code: -32603, message: "Unexpected response format")
            }
        }
    }
}

extension APIClient {
    /// Updates all segwit inputs and outputs in a PSBT with data from output descriptors, the UTXO set or the mempool.
    /// - Parameters:
    ///   - psbt: A base64 string of a PSBT.
    ///   - descriptors: An array of either strings or `UTXOUpdatePSBTDescriptor` objects.
    /// - Returns: The base64-encoded partially signed transaction with inputs updated.
    /// - Throws: `JSONRPCError` if the node returns an error, or other `Error` types for network or decoding issues.
    public func utxoUpdatePSBT(psbt: String, descriptors: [Any]? = nil) async throws -> String {
        var params: [Codable] = [psbt]
        if let descriptors = descriptors {
            params.append(descriptors)
        }
        return try await command(.utxoUpdatePSBT, params: params)
    }
}
