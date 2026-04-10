//
//  FinalizedPSBT.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Result of `finalizepsbt`.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct FinalizedPSBT: Codable, Sendable, Equatable {
    /// The base64-encoded partially signed transaction (if not fully extracted).
    public let psbt: String?

    /// The hex-encoded network transaction (if `complete` and `extract` was true).
    public let hex: String?

    /// Whether the PSBT is fully signed and ready to broadcast.
    public let complete: Bool
}
