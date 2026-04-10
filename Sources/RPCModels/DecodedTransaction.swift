//
//  DecodedTransaction.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
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
    public let txid: String
    public let hash: String
    public let size: Int
    public let vsize: Int
    public let weight: Int
    public let version: Int
    public let locktime: Int64
    public let vin: [Vin]
    public let vout: [Vout]
}
