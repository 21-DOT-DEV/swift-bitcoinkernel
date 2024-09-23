//
//  BlockchainInfo.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

public struct BlockchainInfo: Codable {
    public let chain: String
    public let blocks: Int
    public let headers: Int
    public let bestblockhash: String
    public let difficulty: Double
    public let mediantime: Int
    public let verificationprogress: Double
    public let initialblockdownload: Bool
    public let chainwork: String
    public let size_on_disk: Int64
    public let pruned: Bool
    public let pruneheight: Int?
    public let automatic_pruning: Bool?
    public let prune_target_size: Int64?
    public let softforks: [String: SoftFork]
    public let warnings: String

    public struct SoftFork: Codable {
        public let type: String
        public let bip9: BIP9?
        public let height: Int?
        public let active: Bool

        public struct BIP9: Codable {
            public let status: String
            public let bit: Int?
            public let start_time: Int64
            public let timeout: Int64
            public let since: Int
            public let statistics: Statistics?

            public struct Statistics: Codable {
                public let period: Int
                public let threshold: Int
                public let elapsed: Int
                public let count: Int
                public let possible: Bool
            }
        }
    }
}
