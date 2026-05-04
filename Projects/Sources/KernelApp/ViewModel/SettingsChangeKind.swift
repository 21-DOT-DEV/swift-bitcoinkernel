//
//  SettingsChangeKind.swift
//  21-DOT-DEV/Bitcoin
//
//  Classifies a diff between two ``KernelAppSettings`` snapshots into
//  the action ``KernelAppViewModel`` must take — none, respawn the
//  sync, or teardown+rebuild the kernel.
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import BitcoinKernel
import Foundation

// MARK: - KernelAppSettingsSnapshot

/// Immutable capture of the kernel-affecting subset of
/// ``KernelAppSettings``.
///
/// Consumed by ``SettingsChangeKind/classify(previous:current:)`` to decide
/// what the view model must do after a settings mutation. Intentionally
/// excludes logging settings — those are applied globally via
/// ``LoggingConnection`` and do not require VM action.
///
/// Stored by value on ``KernelAppViewModel`` as `lastAppliedSnapshot`; the
/// VM refreshes it after every successful `start()`, `requestReindex(_:)`,
/// and `applySettingsChange()`.
struct KernelAppSettingsSnapshot: Equatable, Sendable {
    let chainType: ChainType
    let effectiveDataDirectory: URL
    let workerThreadCount: Int32
    let blockSourceEndpoint: URL?
    let routeDownloadsThroughTor: Bool
}

extension KernelAppSettingsSnapshot {
    /// Captures the current kernel-affecting state of ``KernelAppSettings``.
    @MainActor
    init(settings: KernelAppSettings) {
        self.init(
            chainType: settings.chainType,
            effectiveDataDirectory: settings.effectiveDataDirectory,
            workerThreadCount: settings.workerThreadCount,
            blockSourceEndpoint: settings.blockSourceEndpoint,
            routeDownloadsThroughTor: settings.routeDownloadsThroughTor
        )
    }
}

// MARK: - SettingsChangeKind

/// What action the view model must take in response to a settings change.
///
/// Ordered from least to most aggressive;
/// ``classify(previous:current:)`` returns the most aggressive action
/// implied by the diff (kernel changes win over sync-only changes).
enum SettingsChangeKind: Equatable, Sendable {
    /// No effective change — no-op.
    case none

    /// Cancel the running sync and respawn with a fresh block source.
    /// The resident kernel is preserved. Used for `blockSourceEndpoint`
    /// and `routeDownloadsThroughTor` changes.
    case restartSync

    /// Teardown the kernel, reopen against the new settings, then
    /// respawn sync. Used for `chainType`, `effectiveDataDirectory`,
    /// and `workerThreadCount` — settings consulted only at
    /// ``ChainstateManager`` construction time.
    case restartKernel
}

extension SettingsChangeKind {
    /// Compute the action required to go from `previous` to `current`.
    ///
    /// - Returns: The most aggressive action implied by the diff. Kernel
    ///   restarts supersede sync restarts; identical snapshots return
    ///   ``none``.
    static func classify(
        previous: KernelAppSettingsSnapshot,
        current: KernelAppSettingsSnapshot
    ) -> SettingsChangeKind {
        if previous == current { return .none }

        // Kernel-affecting changes win — these options are consulted
        // only at ChainstateManager construction, so any change demands
        // a rebuild.
        if previous.chainType != current.chainType
            || previous.effectiveDataDirectory != current.effectiveDataDirectory
            || previous.workerThreadCount != current.workerThreadCount {
            return .restartKernel
        }

        // Source-only changes — kernel stays up, sync task restarts.
        if previous.blockSourceEndpoint != current.blockSourceEndpoint
            || previous.routeDownloadsThroughTor != current.routeDownloadsThroughTor {
            return .restartSync
        }

        // Unreachable given the current field set, but defensive: if
        // equality failed above yet none of the tracked fields differ,
        // the delta is outside this snapshot's remit.
        return .none
    }
}
