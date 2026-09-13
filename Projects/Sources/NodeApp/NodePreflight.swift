//
//  NodePreflight.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Whether device conditions allow starting the node at all.
///
/// A companion to `NodeAutomation`, which decides *which step* a run takes once a
/// run is worth doing; this decides whether it is worth doing. Both are plain
/// values with no Shortcuts, SwiftUI or UIKit types, so they are unit-testable on
/// every platform in CI without a device.
///
/// Starting a full Bitcoin node runs for minutes and writes continuously. There are
/// seven conditions under which doing so is either impossible or actively harmful,
/// and in each case a run that says so is more useful than one that starts and
/// quietly achieves nothing. See
/// `Development/Specs/003-node-automation-action/plan.md` §3.6, which still lists
/// six — the seventh is the chain folder below, and the plan is reconciled when the
/// feature lands.
///
/// Nothing calls this yet. The code that *reads* these conditions from the device is
/// framework-dependent and cannot be exercised in CI, so it lands with the
/// node-start work alongside its caller; only the decision lands here.
enum NodePreflight {

    /// What was observed about the device, as plain values.
    ///
    /// Defaults describe a healthy device, so a test states only the condition it
    /// cares about.
    struct DeviceConditions: Equatable {
        /// Whether the app's own files can be read right now. False only between a
        /// restart and the person's first unlock: the app's files use the platform
        /// default protection, which is readable while merely locked but not before
        /// that first unlock. Verified against the app's declared permissions, which
        /// request no stricter protection.
        var filesReadable: Bool = true
        /// Whether the folder the chain is written into exists.
        ///
        /// Deliberately only about the folder existing. Preparing it also asks the
        /// system to keep it out of backups, and that request can fail on its own —
        /// but a folder that exists and is not marked is still perfectly writable, so
        /// the node runs and only backups may grow. That failure is logged where it
        /// happens and is not a reason to decline a run.
        var chainFolderExists: Bool = true
        /// Whether the person has switched on the battery saver.
        var lowPowerModeEnabled: Bool = false
        /// Whether the current network is metered — cellular, or a link shared from
        /// another phone. Catching up a chain moves gigabytes, so a run here can
        /// cost the person real money.
        var networkIsMetered: Bool = false
        /// Whether the person has switched on Low Data Mode for this network, asking
        /// the system to use as little data as possible. Checked separately from
        /// `networkIsMetered`, because Low Data Mode on home wireless is restricted
        /// but not metered, and either one alone should stop a multi-gigabyte sync.
        var networkIsDataRestricted: Bool = false
        /// Whether the device is already too hot (its heat level is serious or worse).
        var overheating: Bool = false
        /// Free space on the volume holding the chain data, or `nil` if unknown.
        /// Unknown is never treated as too little — refusing on a failed reading
        /// would ground every run on a device whose free space cannot be queried.
        var freeDiskBytes: Int64? = nil
    }

    /// Why a run declined to start the node.
    enum Refusal: Equatable {
        /// The app's files are not readable yet (restart, before the first unlock).
        case filesNotReadable
        /// The folder the chain is written into does not exist and could not be
        /// created, so there is nowhere to put the data.
        case chainFolderMissing
        /// Too little room for a node that writes continuously.
        case notEnoughDisk(freeBytes: Int64)
        /// The network is metered, so a sync could cost the person real money.
        case meteredNetwork
        /// The person asked this network to use as little data as possible.
        case dataRestrictedNetwork
        /// The device is already too hot to add sustained work to.
        case overheating
        /// The person asked the device to save battery.
        case lowPowerMode

        /// The single sentence a person sees. Kept beside the case so adding a
        /// reason cannot compile without wording.
        var message: String {
            switch self {
            case .filesNotReadable:
                return "The node's files are not readable until the phone is unlocked once after a restart, so the node did not start."
            case .chainFolderMissing:
                // Says what is actually wrong. An earlier wording blamed backups here,
                // which was misleading: a failed backup mark no longer stops a run, so
                // the only way to reach this sentence is that there is nowhere to write.
                return "There is nowhere to write the blockchain data, so the node did not start."
            case let .notEnoughDisk(freeBytes):
                // Formatted by the platform rather than by hand. Hand-building this
                // divided by 1024³ while labelling the result "GB" — which means the
                // smaller decimal gigabyte — overstating free space by about 7%; and
                // formatting to one decimal place rounded *up*, so one byte under the
                // floor printed as "1.0 GB is too little", contradicting itself. The
                // file style matches the figure the device's own storage screen shows,
                // which is the number a person would act on, and it comes out
                // translated in other languages for free.
                let free = freeBytes.formatted(.byteCount(style: .file))
                return
                    "Only \(free) of free space is left, which is too little to sync safely, so the node did not start."
            case .meteredNetwork:
                return "The current network is metered — cellular, or a link shared from another phone — and syncing can use gigabytes, so the node did not start."
            case .dataRestrictedNetwork:
                return "Low Data Mode is on for this network, so the node did not start."
            case .overheating:
                return "The device is too warm to sync right now, so the node did not start."
            case .lowPowerMode:
                return "Low Power Mode is on, so the node did not start."
            }
        }
    }

    /// The least free space a run will start on.
    ///
    /// A judgment call, not a measured figure: the app's default pruned target keeps
    /// roughly 550 MB of blocks, and the node needs working room above that to write
    /// and compact without failing. One gigabyte is that target plus headroom,
    /// deliberately conservative because filling the disk is far worse than skipping
    /// a run. Tunable — it is a parameter below so tests do not depend on it.
    static let minimumFreeDiskBytes: Int64 = 1_073_741_824

    /// The reason to decline, or `nil` when the run may start.
    ///
    /// Ordered most to least fundamental, so the reported reason is the one that
    /// matters most when several apply: unreadable files make a run impossible; a
    /// missing chain folder likewise, and it is weighed before free space because
    /// free space is measured *on that folder* and cannot be read until it exists;
    /// too little disk risks damage; a metered network can cost real money; a
    /// data-restricted network is the person's stated preference about data; heat
    /// makes things worse; battery saver is a stated preference about power and so
    /// is checked last.
    ///
    /// Both network conditions are checked, and ahead of the two "makes things
    /// worse" conditions, because spending someone's mobile data allowance without
    /// asking is the one outcome here that costs them money rather than battery.
    static func refusal(
        for conditions: DeviceConditions,
        minimumFreeDiskBytes: Int64 = minimumFreeDiskBytes
    ) -> Refusal? {
        if !conditions.filesReadable { return .filesNotReadable }
        if !conditions.chainFolderExists { return .chainFolderMissing }
        if let free = conditions.freeDiskBytes, free < minimumFreeDiskBytes {
            return .notEnoughDisk(freeBytes: free)
        }
        if conditions.networkIsMetered { return .meteredNetwork }
        if conditions.networkIsDataRestricted { return .dataRestrictedNetwork }
        if conditions.overheating { return .overheating }
        if conditions.lowPowerModeEnabled { return .lowPowerMode }
        return nil
    }
}
