//
//  RawTransaction.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
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
    public let txid: String
    public let hash: String
    public let size: Int
    public let vsize: Int
    public let weight: Int
    public let version: Int
    public let locktime: Int64
    public let vin: [Vin]
    public let vout: [Vout]
    public let hex: String
    public let blockhash: String?
    public let confirmations: Int?
    public let time: UnixTimestamp?
    public let blocktime: UnixTimestamp?

    /// Whether the transaction is in the active chain (only for `blockhash` lookups).
    public let inActiveChain: Bool?

    enum CodingKeys: String, CodingKey {
        case txid, hash, size, vsize, weight, version, locktime
        case vin, vout, hex, blockhash, confirmations, time, blocktime
        case inActiveChain = "in_active_chain"
    }
}
