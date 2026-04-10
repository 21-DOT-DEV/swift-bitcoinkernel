//
//  Vout.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// A transaction output.
public struct Vout: Codable, Sendable, Equatable {
    /// The value in BTC.
    public let value: BTCAmount

    /// The output index (n).
    public let n: Int

    /// The scriptPubKey.
    public let scriptPubKey: ScriptPubKey
}
