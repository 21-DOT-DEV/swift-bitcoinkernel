//
//  MempoolAcceptResult.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Result of `testmempoolaccept` for a single transaction.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct MempoolAcceptResult: Codable, Sendable, Equatable {
    public let txid: String
    public let wtxid: String
    public let allowed: Bool?
    public let vsize: Int?
    public let fees: MempoolAcceptFees?

    /// Rejection reason (only present when `allowed` is false).
    public let rejectReason: String?

    enum CodingKeys: String, CodingKey {
        case txid, wtxid, allowed, vsize, fees
        case rejectReason = "reject-reason"
    }
}

/// Fee details for an accepted mempool test.
public struct MempoolAcceptFees: Codable, Sendable, Equatable {
    /// Transaction fee in BTC.
    public let base: BTCAmount

    /// Effective fee rate in BTC/kvB.
    public let effectiveFeerate: Double?

    /// Transactions whose fees were considered (txids).
    public let effectiveIncludes: [String]?

    enum CodingKeys: String, CodingKey {
        case base
        case effectiveFeerate = "effective-feerate"
        case effectiveIncludes = "effective-includes"
    }
}
