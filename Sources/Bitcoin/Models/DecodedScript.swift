//
//  DecodedScript.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Result of `decodescript`.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct DecodedScript: Codable, Sendable, Equatable {
    /// Script public key in assembly representation.
    public let asm: String

    /// Script type (e.g., "pubkeyhash", "scripthash", "witness_v0_keyhash").
    public let type: String

    /// Bitcoin address (if applicable).
    public let address: String?

    /// Descriptor for the script.
    public let desc: String?

    /// Required signatures (deprecated).
    public let reqSigs: Int?

    /// Associated addresses (deprecated).
    public let addresses: [String]?

    /// Address of P2SH-wrapped script.
    public let p2sh: String?

    /// Segwit info for P2SH-embedded witness scripts.
    public let segwit: DecodedScriptSegwit?
}

/// Segwit details within a decoded script.
public struct DecodedScriptSegwit: Codable, Sendable, Equatable {
    /// Script public key in assembly representation.
    public let asm: String
    /// The raw script bytes, hex-encoded.
    public let hex: String
    /// The script type.
    public let type: String
    /// The Bitcoin address (if applicable).
    public let address: String?
    /// Descriptor for the script.
    public let desc: String?
    /// Required signatures (deprecated).
    public let reqSigs: Int?
    /// Associated addresses (deprecated).
    public let addresses: [String]?

    /// P2SH address for this witness script.
    public let p2shSegwit: String?

    enum CodingKeys: String, CodingKey {
        case asm, hex, type, address, desc, reqSigs, addresses
        case p2shSegwit = "p2sh-segwit"
    }
}
