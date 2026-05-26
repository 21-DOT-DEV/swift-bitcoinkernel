//
//  IndexInfo.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Per-index status from `getindexinfo`.
///
/// The RPC returns `{ "indexname": { synced: ..., best_block_height: ... }, ... }`.
/// Decode as `[String: IndexInfo]`.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct IndexInfo: Codable, Sendable, Equatable {
    /// Whether the index is synced.
    public let synced: Bool

    /// The block height to which the index is synced.
    public let bestBlockHeight: Int

    enum CodingKeys: String, CodingKey {
        case synced
        case bestBlockHeight = "best_block_height"
    }
}
