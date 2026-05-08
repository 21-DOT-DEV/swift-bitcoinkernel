//
//  LastProcessedBlock.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// The last block processed by the wallet, included in many wallet RPC responses.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct LastProcessedBlock: Codable, Sendable, Equatable, CustomStringConvertible {
    /// The hash of the last processed block.
    public let hash: String

    /// The height of the last processed block.
    public let height: Int

    public var description: String { "#\(height) \(hash.prefix(16))…" }
}
