//
//  ScriptSig.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
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
