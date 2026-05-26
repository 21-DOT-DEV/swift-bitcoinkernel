//
//  SynchronizationState.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Kernel-internal synchronization phase, passed to
/// ``NotificationCallbacks/blockTip`` and
/// ``NotificationCallbacks/headerTip`` on every tip update.
///
/// Lets observers distinguish "we're still catching up" events (when
/// tip updates should not trigger user-visible notifications) from
/// steady-state events.
///
/// > Important: This is **distinct from** ``BlockchainSync/Update/State-swift.enum``
/// — they solve different problems. `SynchronizationState` is the
/// kernel's internal IBD-or-not flag (relevant to notification callback
/// consumers); `BlockchainSync.Update.State` is the sync engine's own
/// lifecycle enum (relevant to sync-sequence consumers).
///
/// Maps to `btck_SynchronizationState` constants in the kernel C API.
public enum SynchronizationState: UInt8, Sendable, CaseIterable, Codable, CustomStringConvertible {
    /// Initial reindex of blocks from on-disk block files.
    case initReindex  = 0

    /// Initial Block Download — catching up to the current chain tip
    /// from network peers.
    case initDownload = 1

    /// Normal operation after initial synchronization is complete.
    /// Tip updates at this state represent real-time new blocks.
    case postInit     = 2

    /// A short lowercase label (`"reindexing"` / `"downloading"` /
    /// `"synchronized"`) suitable for status display.
    public var description: String {
        switch self {
        case .initReindex:  return "reindexing"
        case .initDownload: return "downloading"
        case .postInit:     return "synchronized"
        }
    }
}
