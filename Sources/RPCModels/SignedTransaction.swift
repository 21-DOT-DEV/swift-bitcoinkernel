//
//  SignedTransaction.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
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
    public let txid: String
    public let vout: Int
    public let scriptSig: String
    public let sequence: Int64
    public let error: String
}
