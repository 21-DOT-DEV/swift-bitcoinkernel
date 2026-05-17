//
//  RescanResult.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Result of `rescanblockchain`.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct RescanResult: Codable, Sendable, Equatable {
    /// The block height where the rescan started (inclusive).
    public let start_height: Int // swiftlint:disable:this identifier_name

    /// The block height where the rescan stopped (inclusive).
    public let stop_height: Int // swiftlint:disable:this identifier_name
}
