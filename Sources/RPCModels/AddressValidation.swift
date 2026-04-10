//
//  AddressValidation.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Result of `validateaddress`.
///
/// When `isvalid` is false, only `isvalid` is populated.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct AddressValidation: Codable, Sendable, Equatable {
    public let isvalid: Bool
    public let address: String?
    public let scriptPubKey: String?
    public let isscript: Bool?
    public let iswitness: Bool?
    public let witnessVersion: Int?
    public let witnessProgram: String?

    enum CodingKeys: String, CodingKey {
        case isvalid, address, scriptPubKey, isscript, iswitness
        case witnessVersion = "witness_version"
        case witnessProgram = "witness_program"
    }
}
