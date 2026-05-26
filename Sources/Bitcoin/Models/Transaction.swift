//
//  Transaction.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Represents a Bitcoin transaction as returned in verbose block/transaction RPCs.
///
/// Contains the full decoded transaction with inputs and outputs.
/// Fields like `blockhash`, `blocktime`, `confirmations` are present when the
/// transaction is confirmed (absent for mempool transactions in some contexts).
public struct Transaction: Codable, Sendable, Equatable {
    /// The transaction id.
    public let txid: String

    /// The transaction hash (differs from txid for witness transactions).
    public let hash: String

    /// The transaction version.
    public let version: Int

    /// The serialized transaction size in bytes.
    public let size: Int

    /// The virtual transaction size (weight / 4).
    public let vsize: Int

    /// The transaction weight (BIP 141).
    public let weight: Int

    /// The lock time.
    public let locktime: Int64

    /// The transaction inputs.
    public let vin: [Vin]

    /// The transaction outputs.
    public let vout: [Vout]

    /// The serialized hex-encoded transaction data.
    public let hex: String?

    /// The block hash containing this transaction (absent for unconfirmed).
    public let blockhash: String?

    /// The number of confirmations (absent for unconfirmed).
    public let confirmations: Int?

    /// The block time in epoch seconds (absent for unconfirmed).
    public let blocktime: UnixTimestamp?

    /// The time the transaction was received (absent in block context).
    public let time: UnixTimestamp?

    /// The transaction fee in BTC (present in wallet context, absent in raw).
    public let fee: BTCAmount?
}