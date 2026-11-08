//
//  FakeDeviceReadings.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import Synchronization
@testable import NodeApp

// `NodeRun` and `NodeRunReport` exist only in phone and tablet builds — the
// same compile-time gate as the sources, so these helpers are empty on a
// Mac build.
#if os(iOS)

/// The device readings, scripted field by field — the seam's other half.
/// Defaults are permissive (files readable, folder there, network cheap,
/// plenty of disk) so a test that never consults conditions needs no setup;
/// a start-path test can park `firstNetworkReport` to drive the gather's
/// bounded wait, or flip a field while the run is in flight.
///
/// The reads whose order the run relies on are recorded in `calls`, in the
/// order made — a test pinning "files were checked before the folder was
/// prepared" compares positions in that list rather than inferring order
/// from side effects. The drift gather's three reads join the same log,
/// where the count, not the order, is what proves the gather ran on every
/// watch pass.
@MainActor
final class FakeDeviceReadings: DeviceReadings {
    /// Each `DeviceReadings` member name, in the order the run read it —
    /// a `Mutex` because `networkFirst` deliberately reads off-actor.
    let calls = Mutex<[String]>([])

    var startWatchingCalls = 0
    /// The scripted value behind `protectedDataAvailable`; the read itself
    /// is recorded, which is what lets the ordering tests see it.
    var isProtectedDataAvailable = true
    /// The scripted value behind `lowPowerModeEnabled`; a test flips it
    /// mid-watch to script the delta the drift check refuses on.
    var isLowPowerModeEnabled = false
    /// The scripted value behind `thermalState`; flippable mid-watch.
    var scriptedThermalState: ProcessInfo.ThermalState = .nominal
    var chainFolderPrepared = true
    var freeDiskBytesResult: Int64? = 1 << 40
    /// The scripted value behind `networkCurrent`; flippable mid-watch.
    var scriptedNetworkCurrent: NetworkCost = .unknown
    /// A `let`, not a `var`: `networkFirst` is `nonisolated` to stay off the
    /// main actor like the production read, and only an immutable member is
    /// reachable without the hop a `var` would force.
    let firstNetworkReport: @Sendable () async -> NetworkCost

    /// `nonisolated` so `FakeRunSession(device:)`'s default value — evaluated
    /// at a nonisolated call site — may construct one.
    nonisolated init(
        firstNetworkReport: @escaping @Sendable () async -> NetworkCost = {
            NetworkCost(isMetered: false, isDataRestricted: false)
        }
    ) {
        self.firstNetworkReport = firstNetworkReport
    }

    var protectedDataAvailable: Bool {
        calls.withLock { $0.append("protectedDataAvailable") }
        return isProtectedDataAvailable
    }

    var lowPowerModeEnabled: Bool {
        calls.withLock { $0.append("lowPowerModeEnabled") }
        return isLowPowerModeEnabled
    }

    var thermalState: ProcessInfo.ThermalState {
        calls.withLock { $0.append("thermalState") }
        return scriptedThermalState
    }

    var networkCurrent: NetworkCost {
        calls.withLock { $0.append("networkCurrent") }
        return scriptedNetworkCurrent
    }

    func startWatchingNetworkCost() {
        startWatchingCalls += 1
        calls.withLock { $0.append("startWatchingNetworkCost") }
    }

    func prepareChainFolder() -> Bool {
        calls.withLock { $0.append("prepareChainFolder") }
        return chainFolderPrepared
    }

    func freeDiskBytes() -> Int64? {
        calls.withLock { $0.append("freeDiskBytes") }
        return freeDiskBytesResult
    }

    nonisolated func networkFirst() async -> NetworkCost {
        calls.withLock { $0.append("networkFirst") }
        return await firstNetworkReport()
    }
}

#endif
