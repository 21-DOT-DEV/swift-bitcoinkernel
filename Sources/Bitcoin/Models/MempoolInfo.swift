//
//  MempoolInfo.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Active state of the transaction memory pool from `getmempoolinfo`.
///
/// Fee rate fields (`mempoolminfee`, `minrelaytxfee`, `incrementalrelayfee`)
/// are in **BTC/kvB** (not satoshis, not `BTCAmount`).
///
/// - Note: Targets Bitcoin Core v31.x. Fields marked optional were added in v24+.
public struct MempoolInfo: Codable, Sendable, Equatable {
    /// Whether the mempool is fully loaded.
    public let loaded: Bool

    /// Current transaction count.
    public let size: Int

    /// Sum of all virtual transaction sizes (BIP 141).
    public let bytes: Int

    /// Total memory usage for the mempool in bytes.
    public let usage: Int

    /// Total fees of all transactions in the mempool in BTC (v22+).
    public let totalFee: BTCAmount?

    /// Maximum memory usage for the mempool in bytes.
    public let maxmempool: Int

    /// Minimum fee rate in BTC/kvB for tx to be accepted.
    public let mempoolminfee: Double

    /// Current minimum relay fee for transactions in BTC/kvB.
    public let minrelaytxfee: Double

    /// Minimum fee rate increment for mempool limiting or replacement in BTC/kvB (v24+).
    public let incrementalrelayfee: Double?

    /// Current number of transactions that haven't passed initial broadcast yet.
    public let unbroadcastcount: Int

    /// Whether the node has full replace-by-fee enabled (v24+).
    public let fullrbf: Bool?

    enum CodingKeys: String, CodingKey {
        case loaded, size, bytes, usage, maxmempool, mempoolminfee, minrelaytxfee
        case incrementalrelayfee, unbroadcastcount, fullrbf
        case totalFee = "total_fee"
    }
}
