//
//  SendResult.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Result of the `send` or `sendall` wallet RPC.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct SendResult: Codable, Sendable, Equatable {
    /// Whether the transaction is fully signed and ready to broadcast.
    public let complete: Bool

    /// The transaction id (if complete).
    public let txid: String?

    /// The hex-encoded raw transaction (if complete).
    public let hex: String?

    /// The PSBT base64 string (if not complete, needs more signatures).
    public let psbt: String?
}
