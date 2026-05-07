//
//  MempoolFees.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Fee breakdown for a mempool entry. All amounts in BTC.
///
/// Nested under the `fees` key in `getmempoolentry` / verbose mempool RPCs.
public struct MempoolFees: Codable, Sendable, Equatable {
    /// Transaction fee in BTC.
    public let base: BTCAmount

    /// Transaction fee with fee deltas used for mining priority in BTC.
    public let modified: BTCAmount

    /// Modified fees of in-mempool ancestors (including this one) in BTC.
    public let ancestor: BTCAmount

    /// Modified fees of in-mempool descendants (including this one) in BTC.
    public let descendant: BTCAmount
}
