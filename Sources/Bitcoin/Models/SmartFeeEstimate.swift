//
//  SmartFeeEstimate.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Result of `estimatesmartfee`.
///
/// `feerate` is in **BTC/kvB** (a rate, not an amount — `Double`, not `BTCAmount`).
///
/// - Note: Targets Bitcoin Core v31.x.
public struct SmartFeeEstimate: Codable, Sendable, Equatable {
    /// Estimated fee rate in BTC/kvB (absent if estimation failed).
    public let feerate: Double?

    /// Errors encountered during processing.
    public let errors: [String]?

    /// Block number where estimate was found.
    public let blocks: Int
}
