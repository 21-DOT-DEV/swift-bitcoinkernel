//
//  BumpFeeResult.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Result of `bumpfee`.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct BumpFeeResult: Codable, Sendable, Equatable {
    /// The new transaction id (only if not a PSBT bump).
    public let txid: String?

    /// The original fee in BTC.
    public let origfee: BTCAmount

    /// The new fee in BTC.
    public let fee: BTCAmount

    /// Errors encountered during the bump.
    public let errors: [String]?
}

/// Result of `psbtbumpfee`.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct PSBTBumpFeeResult: Codable, Sendable, Equatable {
    /// The PSBT base64 string of the bumped transaction.
    public let psbt: String

    /// The original fee in BTC.
    public let origfee: BTCAmount

    /// The new fee in BTC.
    public let fee: BTCAmount

    /// Errors encountered during the bump.
    public let errors: [String]?
}
