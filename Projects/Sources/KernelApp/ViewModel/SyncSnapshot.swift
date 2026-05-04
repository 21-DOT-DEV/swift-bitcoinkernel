//
//  SyncSnapshot.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import BitcoinKernel
import Foundation

// MARK: - SyncSnapshot

/// Single, observable snapshot of sync state — the surface
/// ``KernelAppViewModel`` exposes to SwiftUI.
///
/// Translates the typed ``BlockchainSync/Update`` stream into a flat,
/// SwiftUI-bindable struct so views don't need to consume the
/// `AsyncSequence` themselves. Status text is computed once, in this
/// adapter, rather than scattered across each view.
///
/// Adds an ``Phase/idle`` case (the stream has no idle — it's always in
/// some active state when iterating) so views can render a coherent
/// "stopped" state before/after any sync run.
struct SyncSnapshot: Sendable, Equatable {

    /// Lifecycle phase as the view model sees it. Mirrors
    /// ``BlockchainSync/Update/State-swift.enum`` plus an ``idle`` case
    /// for the stopped state outside any sync run.
    enum Phase: Sendable, Equatable {
        case idle
        case preparing
        case syncing
        case finished
        case failed(String)

        /// `true` when sync is in flight — used by ``KernelAppViewModel``
        /// to gate destructive settings changes (chain switch, reindex).
        var isActive: Bool {
            switch self {
            case .preparing, .syncing: return true
            case .idle, .finished, .failed: return false
            }
        }
    }

    var phase: Phase
    var statusText: String
    var localHeight: Int
    var remoteHeight: Int
    var tipHash: Data
    var verificationProgress: Double

    // MARK: - Factories

    /// Snapshot rendered when no sync run is active — view-model start state
    /// and post-stop state.
    static let idle = SyncSnapshot(
        phase: .idle,
        statusText: "Idle",
        localHeight: 0,
        remoteHeight: 0,
        tipHash: Data(),
        verificationProgress: 0.0
    )

    /// Translate a ``BlockchainSync/Update`` into the view-model snapshot
    /// shape. Status-text formatting lives here, in one place, instead of
    /// inside each view.
    init(from update: BlockchainSync.Update) {
        let local = update.tip.height
        let remote = update.remoteTip.height
        self.localHeight = local
        self.remoteHeight = remote
        self.tipHash = update.tip.hash
        self.verificationProgress = update.verificationProgress

        switch update.state {
        case .preparing:
            self.phase = .preparing
            self.statusText = "Preparing"
        case .syncing:
            self.phase = .syncing
            self.statusText = "Validated block \(local) of \(remote)"
        case .finished:
            self.phase = .finished
            self.statusText = "Sync complete"
        case .failed(let reason):
            self.phase = .failed(reason)
            self.statusText = "Sync failed: \(reason)"
        }
    }

    /// Memberwise initializer for the ``idle`` factory and tests.
    init(
        phase: Phase,
        statusText: String,
        localHeight: Int,
        remoteHeight: Int,
        tipHash: Data,
        verificationProgress: Double
    ) {
        self.phase = phase
        self.statusText = statusText
        self.localHeight = localHeight
        self.remoteHeight = remoteHeight
        self.tipHash = tipHash
        self.verificationProgress = verificationProgress
    }
}
