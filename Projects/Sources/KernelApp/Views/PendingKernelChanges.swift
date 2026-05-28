//
//  PendingKernelChanges.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2022-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

//  Draft-state value type for the Settings tab's "pending changes"
//  banner. Represents the subset of KernelAppSettings whose changes
//  require a full kernel rebuild (the `.restartKernel` bucket of
//  SettingsChangeKind). Edits to these fields stage into a
//  PendingKernelChanges until the user commits via Apply; the view
//  model's `applySettingsChange()` then tears down and rebuilds the
//  kernel once for all committed fields.
//
//  The non-kernel-restarting fields (block source, Tor toggle,
//  logging) live-bind straight through to `KernelAppSettings` in
//  the view layer — they don't pass through this type.

import BitcoinKernel
import Foundation

// MARK: - PendingKernelChanges

/// Staged, pending-apply changes to the kernel-affecting subset of
/// ``KernelAppSettings``. All properties are optional / opt-in — an
/// empty draft is a no-op under ``apply(to:)``.
///
/// ### Why the split
///
/// ``SettingsChangeKind`` partitions settings into `.none`,
/// `.restartSync`, and `.restartKernel`. Kernel-restart changes are
/// expensive (teardown + reopen LevelDB), so the Settings tab's
/// HIG-aligned UX batches them behind an Apply button. This type is the
/// storage for that batch.
///
/// ### Fields
///
/// - ``chainType``: Target chain. When set, Apply switches networks.
/// - ``workerThreadCount``: Validation worker thread count.
/// - ``clearDataDirectoryOverride``: If `true`, Apply clears
///   ``KernelAppSettings/dataDirectoryOverride`` so the next kernel open
///   uses the default Application-Support path for the current chain.
///   (Setting a *new* override from within the UI is roadmap work —
///   picker + bookmark persistence across sessions.)
struct PendingKernelChanges: Equatable {
    var chainType: ChainType?
    var workerThreadCount: Int32?
    var clearDataDirectoryOverride: Bool = false

    // MARK: - Derived

    /// Number of pending changes. Drives the banner's pluralization.
    var count: Int {
        var c = 0
        if chainType != nil { c += 1 }
        if workerThreadCount != nil { c += 1 }
        if clearDataDirectoryOverride { c += 1 }
        return c
    }

    /// `true` when no fields are staged. Short-circuits the banner and
    /// makes ``apply(to:)`` a guaranteed no-op.
    var isEmpty: Bool { count == 0 }

    /// Banner copy. Empty when ``isEmpty`` is `true` so callers can
    /// use it in a plain string binding without conditionals.
    var summaryText: String {
        switch count {
        case 0:  return ""
        case 1:  return "1 pending change — Apply will restart the kernel"
        default: return "\(count) pending changes — Apply will restart the kernel"
        }
    }

    // MARK: - Commit

    /// Writes the staged values onto `settings`. Unset fields are left
    /// untouched. After calling this, the caller should invoke
    /// ``KernelAppViewModel/applySettingsChange()`` to make the view
    /// model reconcile (one kernel rebuild for all committed fields).
    ///
    /// - Parameter settings: Destination settings model. Changes take
    ///   effect immediately via the observed `didSet`s and are
    ///   persisted to `UserDefaults`.
    @MainActor
    func apply(to settings: KernelAppSettings) {
        if let chain = chainType {
            settings.chainType = chain
        }
        if let threads = workerThreadCount {
            settings.workerThreadCount = threads
        }
        if clearDataDirectoryOverride {
            settings.dataDirectoryOverride = nil
        }
    }
}
