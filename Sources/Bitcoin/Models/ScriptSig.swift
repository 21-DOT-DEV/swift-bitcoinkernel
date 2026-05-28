//
//  ScriptSig.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// The scriptSig of a transaction input.
public struct ScriptSig: Codable, Sendable, Equatable {
    /// The disassembled script (asm representation).
    public let asm: String

    /// The hex-encoded script.
    public let hex: String
}
