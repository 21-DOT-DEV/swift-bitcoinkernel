//
//  DescriptorInfo.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Result of `getdescriptorinfo`.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct DescriptorInfo: Codable, Sendable, Equatable {
    /// The descriptor in canonical form (with checksum appended).
    public let descriptor: String

    /// The checksum for the input descriptor.
    public let checksum: String

    /// Whether the descriptor is ranged.
    public let isrange: Bool

    /// Whether the descriptor is solvable.
    public let issolvable: Bool

    /// Whether the input descriptor contained private keys.
    public let hasprivatekeys: Bool
}
