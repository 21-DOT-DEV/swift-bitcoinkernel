//
//  Block.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Represents a block in the Bitcoin blockchain.
public struct Block: Codable, Sendable, Equatable {
    /// The block hash.
    public let hash: String
    
    /// The number of confirmations, or -1 if the block is not on the main chain.
    public let confirmations: Int
    
    /// The block size.
    public let size: Int
    
    /// The block size excluding witness data.
    public let strippedSize: Int
    
    /// The block weight as defined in BIP 141.
    public let weight: Int
    
    /// The block height or index.
    public let height: Int
    
    /// The block version.
    public let version: Int
    
    /// The block version formatted in hexadecimal.
    public let versionHex: String
    
    /// The merkle root.
    public let merkleRoot: String
    
    /// The transaction ids.
    public let tx: [String]
    
    /// The block time in UNIX timestamp.
    public let time: UnixTimestamp
    
    /// The median block time in UNIX timestamp.
    public let medianTime: UnixTimestamp
    
    /// The nonce.
    public let nonce: Int64
    
    /// The bits representing the block difficulty.
    public let bits: String

    /// The difficulty target in hexadecimal.
    public let target: String?
    
    /// The difficulty of this block.
    public let difficulty: Double
    
    /// The total amount of work in the chain up to this block, in hexadecimal.
    public let chainWork: String
    
    /// The number of transactions in the block.
    public let nTx: Int
    
    /// The hash of the previous block.
    public let previousBlockHash: String?
    
    /// The hash of the next block.
    public let nextBlockHash: String?

    enum CodingKeys: String, CodingKey {
        case hash, confirmations, size, weight, height, version, versionHex, tx, time, nonce, bits, target, difficulty, nTx
        case strippedSize = "strippedsize"
        case merkleRoot = "merkleroot"
        case medianTime = "mediantime"
        case chainWork = "chainwork"
        case previousBlockHash = "previousblockhash"
        case nextBlockHash = "nextblockhash"
    }
}