//
//  ChainTip.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// A chain tip from `getchaintips`.
public struct ChainTip: Codable, Sendable, Equatable {
    /// Height of the chain tip.
    public let height: Int

    /// Block hash of the tip.
    public let hash: String

    /// Length of the branch (0 for active chain).
    public let branchlen: Int

    /// Status: "active", "valid-fork", "valid-headers", "headers-only", or "invalid".
    public let status: String
}
