//
//  GeneratedBlock.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Result of `generateblock` — a block mined from specified transactions.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct GeneratedBlock: Codable, Sendable, Equatable {
    /// The hash of the generated block.
    public let hash: String
}
