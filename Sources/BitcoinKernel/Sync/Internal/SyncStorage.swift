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
import Synchronization

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

    /// Producer tasks spawned by ``BlockchainSync/Updates/AsyncIterator``, one
    /// per iteration started.
    ///
    /// Tracked because each producer strongly captures `self`, and therefore
    /// keeps ``manager`` — and the LevelDB lock on its data directory — alive
    /// for as long as it runs. `AsyncStream.onTermination` only *requests*
    /// cancellation; with no handle to await, a caller that stops a sync and
    /// immediately reopens the same data directory races a producer that has
    /// not finished unwinding. See ``BlockchainSync/shutdown()``.
    private let producers = Mutex<[Task<Void, Never>]>([])

    init(manager: ChainstateManager, source: any BlockSource, context: Context) {
        self.manager = manager
        self.source = source
        self.context = context
        self.progress = Progress(totalUnitCount: 0)
    }

    /// Record a newly spawned producer task.
    func track(producer: Task<Void, Never>) {
        producers.withLock { $0.append(producer) }
    }

    /// Remove and return every tracked producer, leaving none behind.
    func drainProducers() -> [Task<Void, Never>] {
        producers.withLock { tasks in
            let drained = tasks
            tasks.removeAll()
            return drained
        }
    }
}
