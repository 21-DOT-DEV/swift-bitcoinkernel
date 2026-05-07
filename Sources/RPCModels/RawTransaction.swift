//
//  RawTransaction.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Verbose transaction from `getrawtransaction` (verbose=true).
///
/// Extends ``DecodedTransaction`` fields with block context and hex.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct RawTransaction: Codable, Sendable, Equatable {
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
    /// The serialized, hex-encoded transaction data.
    public let hex: String
    /// The block hash containing the transaction.
    public let blockhash: String?
    /// The number of confirmations.
    public let confirmations: Int?
    /// The transaction time in seconds since epoch (same as block time).
    public let time: UnixTimestamp?
    /// The block time in seconds since epoch.
    public let blocktime: UnixTimestamp?

    /// Whether the transaction is in the active chain (only for `blockhash` lookups).
    public let inActiveChain: Bool?

    enum CodingKeys: String, CodingKey {
        case txid, hash, size, vsize, weight, version, locktime
        case vin, vout, hex, blockhash, confirmations, time, blocktime
        case inActiveChain = "in_active_chain"
    }
}
