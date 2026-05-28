//
//  SyncStorage.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Internal shared state owned by a ``BlockchainSync`` and its derived
/// ``BlockchainSync/Updates`` sequences. Holds references to the kernel
/// types the sync loop needs plus the `Foundation.Progress` instance
/// exposed on the public API.
///
/// Reference type so the same progress instance survives across
/// ``BlockchainSync/progress`` reads and ``BlockchainSync/updates()``
/// calls (required for `BGContinuedProcessingTask.progress` binding).
final class SyncStorage: @unchecked Sendable {
    let manager: ChainstateManager
    let source: any BlockSource
    let context: Context
    let progress: Progress

    init(manager: ChainstateManager, source: any BlockSource, context: Context) {
        self.manager = manager
        self.source = source
        self.context = context
        self.progress = Progress(totalUnitCount: 0)
    }
}
