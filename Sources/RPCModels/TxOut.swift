//
//  TxOut.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Unspent transaction output from `gettxout`.
///
/// Returns `nil` from `sendNullable` when the output has been spent.
public struct TxOut: Codable, Sendable, Equatable {
    /// The hash of the block at the tip when this was queried.
    public let bestblock: String

    /// The number of confirmations.
    public let confirmations: Int

    /// The transaction amount in BTC.
    public let value: BTCAmount

    /// The scriptPubKey.
    public let scriptPubKey: ScriptPubKey

    /// Whether this is a coinbase transaction.
    public let coinbase: Bool
}
