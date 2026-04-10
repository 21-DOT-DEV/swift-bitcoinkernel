//
//  BlockHeader.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Block header data from `getblockheader` (verbose=true).
public struct BlockHeader: Codable, Sendable, Equatable {
    public let hash: String
    public let confirmations: Int
    public let height: Int
    public let version: Int
    public let versionHex: String
    public let merkleroot: String
    public let time: UnixTimestamp
    public let mediantime: UnixTimestamp
    public let nonce: Int64
    public let bits: String
    public let target: String?
    public let difficulty: Double
    public let chainwork: String
    public let nTx: Int
    public let previousblockhash: String?
    public let nextblockhash: String?
}
