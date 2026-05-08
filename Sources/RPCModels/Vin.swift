//
//  Vin.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// A transaction input.
///
/// For coinbase transactions, `coinbase` is set and `txid`/`vout`/`scriptSig` are absent.
public struct Vin: Codable, Sendable, Equatable {
    /// The txid of the output being spent (absent for coinbase).
    public let txid: String?

    /// The output index being spent (absent for coinbase).
    public let vout: Int?

    /// The scriptSig (absent for coinbase).
    public let scriptSig: ScriptSig?

    /// Coinbase data (hex, present only for coinbase transactions).
    public let coinbase: String?

    /// The witness stack (hex-encoded items).
    public let txinwitness: [String]?

    /// The sequence number.
    public let sequence: Int64
}
