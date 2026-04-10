//
//  MultisigResult.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Result of `createmultisig`.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct MultisigResult: Codable, Sendable, Equatable {
    /// The value of the new multisig address.
    public let address: String

    /// The hex-encoded redemption script.
    public let redeemScript: String

    /// The descriptor for the multisig address.
    public let descriptor: String
}
