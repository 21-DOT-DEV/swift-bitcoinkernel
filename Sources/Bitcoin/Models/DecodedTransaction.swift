//
//  DecodedTransaction.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Decoded transaction from `decoderawtransaction`.
///
/// Pure transaction structure without block context.
/// Reuses ``Vin`` and ``Vout`` from shared types.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct DecodedTransaction: Codable, Sendable, Equatable {
    /// The transaction id.
    public let txid: String
    /// The transaction hash (differs from txid for witness transactions).
    public let hash: String
    /// The serialized transaction size.
    public let size: Int
    /// The virtual transaction size (differs from size for witness transactions).
    public let vsize: Int
    /// The transaction's weight (between `vsize*4-3` and `vsize*4`).
    public let weight: Int
    /// The version.
    public let version: Int
    /// The lock time.
    public let locktime: Int64
    /// The transaction inputs.
    public let vin: [Vin]
    /// The transaction outputs.
    public let vout: [Vout]
}
