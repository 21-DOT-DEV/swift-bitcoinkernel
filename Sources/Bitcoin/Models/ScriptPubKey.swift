//
//  ScriptPubKey.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// The scriptPubKey of a transaction output.
public struct ScriptPubKey: Codable, Sendable, Equatable {
    /// The disassembled script (asm representation).
    public let asm: String

    /// The hex-encoded script.
    public let hex: String

    /// The output type (e.g., "pubkeyhash", "scripthash", "witness_v0_keyhash", "witness_v1_taproot").
    public let type: String

    /// The Bitcoin address (if available for this script type).
    public let address: String?

    /// Number of required signatures (for multisig).
    public let reqSigs: Int?

    /// The associated addresses (legacy, for multisig).
    public let addresses: [String]?

}
