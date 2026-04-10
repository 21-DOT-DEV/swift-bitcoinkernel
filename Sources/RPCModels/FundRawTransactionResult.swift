//
//  FundRawTransactionResult.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Result of `fundrawtransaction`.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct FundRawTransactionResult: Codable, Sendable, Equatable {
    /// The hex-encoded funded raw transaction.
    public let hex: String

    /// The fee added in BTC.
    public let fee: BTCAmount

    /// The position of the added change output, or -1 if none.
    public let changepos: Int
}
