//
//  PSBTAnalysis.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Result of `analyzepsbt`.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct PSBTAnalysis: Codable, Sendable, Equatable {
    /// Per-input analysis.
    public let inputs: [PSBTAnalysisInput]

    /// Estimated vsize of the final signed transaction.
    public let estimatedVsize: Int?

    /// Estimated feerate of the final signed transaction in BTC/kvB.
    public let estimatedFeerate: Double?

    /// The transaction fee paid (only if all UTXO slots filled).
    public let fee: BTCAmount?

    /// Role of the next person that this PSBT needs to go to.
    public let next: String

    /// Error message (if there is one).
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case inputs, fee, next, error
        case estimatedVsize = "estimated_vsize"
        case estimatedFeerate = "estimated_feerate"
    }
}

/// Per-input analysis within `analyzepsbt`.
public struct PSBTAnalysisInput: Codable, Sendable, Equatable {
    /// Whether a UTXO is provided.
    public let hasUtxo: Bool

    /// Whether the input is finalized.
    public let isFinal: Bool

    /// Things that are missing to complete this input.
    public let missing: PSBTMissing?

    /// Role of the next person that this input needs to go to.
    public let next: String?

    enum CodingKeys: String, CodingKey {
        case hasUtxo = "has_utxo"
        case isFinal = "is_final"
        case missing, next
    }
}

/// Missing items for a PSBT input.
public struct PSBTMissing: Codable, Sendable, Equatable {
    /// Public key IDs of keys whose BIP 32 derivation paths are missing.
    public let pubkeys: [String]?

    /// Public key IDs of keys whose signatures are missing.
    public let signatures: [String]?

    /// Hash160 of the missing redeemScript.
    public let redeemscript: String?

    /// SHA256 of the missing witnessScript.
    public let witnessscript: String?
}
