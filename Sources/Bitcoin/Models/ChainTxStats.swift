//
//  ChainTxStats.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Chain transaction statistics from `getchaintxstats`.
public struct ChainTxStats: Codable, Sendable, Equatable {
    /// The timestamp for the final block in the window.
    public let time: UnixTimestamp

    /// The total number of transactions in the chain up to that point.
    public let txcount: Int

    /// The hash of the final block in the window.
    public let windowFinalBlockHash: String

    /// The height of the final block in the window.
    public let windowFinalBlockHeight: Int

    /// Size of the window in number of blocks.
    public let windowBlockCount: Int

    /// The number of transactions in the window (may be absent if window is 0).
    public let windowTxCount: Int?

    /// The elapsed time in the window in seconds.
    public let windowInterval: Int?

    /// The average rate of transactions per second in the window.
    public let txrate: Double?

    enum CodingKeys: String, CodingKey {
        case time, txcount
        case windowFinalBlockHash = "window_final_block_hash"
        case windowFinalBlockHeight = "window_final_block_height"
        case windowBlockCount = "window_block_count"
        case windowTxCount = "window_tx_count"
        case windowInterval = "window_interval"
        case txrate
    }
}
