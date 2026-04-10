//
//  ScanTxOutProgress.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
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
