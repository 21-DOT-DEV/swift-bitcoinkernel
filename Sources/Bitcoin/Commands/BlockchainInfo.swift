//
//  BlockchainInfo.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2024 Timechain Software Initiative 
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Represents information about the current state of the blockchain.
///
/// This struct corresponds to the response of the `getblockchaininfo` RPC command.
public struct BlockchainInfo: Codable, Sendable {
    /// Current network name (main, test, regtest).
    public let chain: String
    
    /// The current number of blocks processed in the server.
    public let blocks: Int
    
    /// The current number of headers we have validated.
    public let headers: Int
    
    /// The hash of the currently best block.
    public let bestblockhash: String
    
    /// The current difficulty.
    public let difficulty: Double
    
    /// The block time in UNIX epoch time.
    public let time: Int
    
    /// Median time for the current best block.
    public let mediantime: Int
    
    /// Estimate of verification progress [0..1].
    public let verificationprogress: Double
    
    /// Estimate of whether this node is in Initial Block Download mode.
    public let initialblockdownload: Bool
    
    /// Total amount of work in active chain, in hexadecimal.
    public let chainwork: String
    
    /// The estimated size of the block and undo files on disk.
    public let sizeOnDisk: Int
    
    /// If the blocks are subject to pruning.
    public let pruned: Bool
    
    /// Lowest-height complete block stored (only present if pruning is enabled).
    public let pruneheight: Int
    
    /// Whether automatic pruning is enabled (only present if pruning is enabled).
    public let automaticPruning: Bool
    
    /// Target size used by pruning (only present if automatic pruning is enabled).
    public let pruneTargetSize: Int
    
    /// Any network and blockchain warnings.
    public let warnings: [String]

    /// Coding keys for mapping JSON keys to struct properties.
    enum CodingKeys: String, CodingKey {
        case chain, blocks, headers, bestblockhash, difficulty, time, mediantime, verificationprogress, initialblockdownload, chainwork
        case sizeOnDisk = "size_on_disk"
        case pruned, pruneheight
        case automaticPruning = "automatic_pruning"
        case pruneTargetSize = "prune_target_size"
        case warnings
    }
}
