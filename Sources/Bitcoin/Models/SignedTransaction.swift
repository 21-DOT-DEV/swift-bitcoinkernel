//
//  SignedTransaction.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Result of `signrawtransactionwithkey`.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct SignedTransaction: Codable, Sendable, Equatable {
    /// The hex-encoded raw transaction with signature(s).
    public let hex: String

    /// Whether the transaction has a complete set of signatures.
    public let complete: Bool

    /// Script verification errors (if any).
    public let errors: [SigningError]?
}

/// A signing error for a specific input.
public struct SigningError: Codable, Sendable, Equatable {
    /// Hex-encoded txid of the outpoint being spent.
    public let txid: String

    /// Output index of the outpoint being spent.
    public let vout: Int

    /// Hex-encoded scriptSig produced for this input.
    public let scriptSig: String

    /// Input sequence number.
    public let sequence: Int64

    /// Verification error message from Bitcoin Core.
    public let error: String
}
