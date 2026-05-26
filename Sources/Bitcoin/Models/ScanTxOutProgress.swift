//
//  ScanTxOutProgress.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
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
