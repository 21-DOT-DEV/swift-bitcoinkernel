//
//  BlockHeader.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Block header data from `getblockheader` (verbose=true).
public struct BlockHeader: Codable, Sendable, Equatable {
    /// The block hash (same as provided).
    public let hash: String
    /// The number of confirmations, or `-1` if the block is not on the main chain.
    public let confirmations: Int
    /// The block height or index.
    public let height: Int
    /// The block version.
    public let version: Int
    /// The block version formatted in hexadecimal.
    public let versionHex: String
    /// The merkle root.
    public let merkleroot: String
    /// The block time expressed in UNIX epoch time.
    public let time: UnixTimestamp
    /// The median block time expressed in UNIX epoch time.
    public let mediantime: UnixTimestamp
    /// The nonce.
    public let nonce: Int64
    /// nBits: compact representation of the block difficulty target.
    public let bits: String
    /// The difficulty target.
    public let target: String?
    /// The difficulty.
    public let difficulty: Double
    /// Expected number of hashes required to produce the current chain.
    public let chainwork: String
    /// The number of transactions in the block.
    public let nTx: Int
    /// The hash of the previous block (if available).
    public let previousblockhash: String?
    /// The hash of the next block (if available).
    public let nextblockhash: String?
}
