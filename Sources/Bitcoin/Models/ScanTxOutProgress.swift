//
//  ScanTxOutProgress.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Progress of a running `scantxoutset` (action=status).
///
/// Returns `nil` from `sendNullable` if no scan is running.
public struct ScanTxOutProgress: Codable, Sendable, Equatable {
    /// Approximate completion percentage [0..100].
    public let progress: Double
}
