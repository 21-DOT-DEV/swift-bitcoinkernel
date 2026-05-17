//
//  SimulateRawTxResult.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Result of `simulaterawtransaction` (v22+).
///
/// - Note: Targets Bitcoin Core v31.x.
public struct SimulateRawTxResult: Codable, Sendable, Equatable {
    /// The wallet balance change (in BTC) as a result of the transaction(s).
    public let balanceChange: BTCAmount

    enum CodingKeys: String, CodingKey {
        case balanceChange = "balance_change"
    }
}
