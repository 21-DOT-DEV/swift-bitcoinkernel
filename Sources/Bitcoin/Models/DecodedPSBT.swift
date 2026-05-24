//
//  DecodedPSBT.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Decoded PSBT from `decodepsbt`.
///
/// The `tx` field uses ``DecodedTransaction`` (same as `decoderawtransaction` output).
///
/// - Note: Targets Bitcoin Core v31.x.
public struct DecodedPSBT: Codable, Sendable, Equatable {
    /// The decoded unsigned transaction.
    public let tx: DecodedTransaction

    /// Unknown global fields (key-value pairs).
    public let unknown: [String: String]?

    /// Per-input PSBT data.
    public let inputs: [PSBTInput]

    /// Per-output PSBT data.
    public let outputs: [PSBTOutput]

    /// Transaction fee paid (only if all UTXO slots filled).
    public let fee: BTCAmount?
}

/// Per-input PSBT data.
public struct PSBTInput: Codable, Sendable, Equatable {
    /// Decoded non-witness UTXO transaction (if present).
    public let nonWitnessUtxo: DecodedTransaction?

    /// Witness UTXO (if present).
    public let witnessUtxo: WitnessUtxo?

    /// Partial signatures (pubkey → signature).
    public let partialSignatures: [String: String]?

    /// Sighash type to be used.
    public let sighash: String?

    /// Redeem script (if present).
    public let redeemScript: PSBTScript?

    /// Witness script (if present).
    public let witnessScript: PSBTScript?

    /// BIP 32 derivation paths.
    public let bip32Derivs: [BIP32Deriv]?

    /// Final scriptSig (if finalized).
    public let finalScriptsig: PSBTScript?

    /// Final witness data (if finalized).
    public let finalScriptwitness: [String]?

    /// Unknown fields.
    public let unknown: [String: String]?

    enum CodingKeys: String, CodingKey {
        case nonWitnessUtxo = "non_witness_utxo"
        case witnessUtxo = "witness_utxo"
        case partialSignatures = "partial_signatures"
        case sighash
        case redeemScript = "redeem_script"
        case witnessScript = "witness_script"
        case bip32Derivs = "bip32_derivs"
        case finalScriptsig = "final_scriptsig"
        case finalScriptwitness = "final_scriptwitness"
        case unknown
    }
}

/// Witness UTXO in a PSBT input.
public struct WitnessUtxo: Codable, Sendable, Equatable {
    /// The value in BTC.
    public let amount: BTCAmount
    /// The output script.
    public let scriptPubKey: ScriptPubKey
}

/// Script representation in PSBT (asm + hex + type).
public struct PSBTScript: Codable, Sendable, Equatable {
    /// The script in assembly representation.
    public let asm: String
    /// The raw script bytes, hex-encoded.
    public let hex: String
    /// The script type (e.g., `pubkeyhash`, `scripthash`).
    public let type: String?
}

/// BIP 32 key derivation path.
public struct BIP32Deriv: Codable, Sendable, Equatable {
    /// The public key this derivation applies to.
    public let pubkey: String?
    /// The fingerprint of the master key.
    public let masterFingerprint: String
    /// The derivation path (e.g., `m/84'/0'/0'/0/0`).
    public let path: String

    enum CodingKeys: String, CodingKey {
        case pubkey
        case masterFingerprint = "master_fingerprint"
        case path
    }
}

/// Per-output PSBT data.
public struct PSBTOutput: Codable, Sendable, Equatable {
    /// Redeem script (if present).
    public let redeemScript: PSBTScript?
    /// Witness script (if present).
    public let witnessScript: PSBTScript?
    /// BIP 32 derivation paths.
    public let bip32Derivs: [BIP32Deriv]?
    /// Unknown fields.
    public let unknown: [String: String]?

    enum CodingKeys: String, CodingKey {
        case redeemScript = "redeem_script"
        case witnessScript = "witness_script"
        case bip32Derivs = "bip32_derivs"
        case unknown
    }
}
