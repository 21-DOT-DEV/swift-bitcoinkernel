//
//  MiningInfo.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Mining-related information from `getmininginfo`.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct MiningInfo: Codable, Sendable, Equatable {
    /// The current block height.
    public let blocks: Int

    /// The block weight of the last assembled block (only present if a block was ever assembled).
    public let currentblockweight: Int?

    /// The number of block transactions of the last assembled block (only present if a block was ever assembled).
    public let currentblocktx: Int?

    /// The current difficulty.
    public let difficulty: Double

    /// The network hashes per second.
    public let networkhashps: Double

    /// The size of the mempool (number of transactions).
    public let pooledtx: Int

    /// Current network name (main, test, signet, regtest).
    public let chain: String

    /// Any network and blockchain warnings.
    public let warnings: [String]
}
