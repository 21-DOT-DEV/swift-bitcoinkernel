//
//  FakeRunSession.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
@testable import NodeApp

// `NodeRun` and `NodeRunReport` exist only in phone and tablet builds — the
// same compile-time gate as the sources, so these helpers are empty on a
// Mac build.
#if os(iOS)

/// The session the run asks, scripted: node state is a plain field so a test
/// can stop the node while a question is in flight — something a real
/// `NodeSession` cannot be made to do — and every answer comes from stored
/// values rather than a controller.
@MainActor
final class FakeRunSession: RunSession {
    var nodeState: NodeState
    var torIsReady = false
    /// The scripted value behind `torIsComingUp(within:)` — `false` by
    /// default, the "dead Tor" reading; a test that wants the wait to hold
    /// scripts `true`.
    var torIsComingUp = false
    /// The scripted delay to the next scheduled attempt, or `nil` for an
    /// attempt already in flight — a horizon-aware reading answers false
    /// only for a delay that outlasts the wait's remaining budget.
    var torRetryDelay: Duration?
    func torIsComingUp(within horizon: Duration) -> Bool {
        torIsComingUp && (torRetryDelay.map { $0 <= horizon } ?? true)
    }
    var torProxyAddress: String?
    var torSessionID: UUID?
    var torSocksPort: UInt16?
    var torStillEnabled = false
    var torStartCalls = 0
    var startNodeResult = false
    var startNodeArguments: [String]?
    let reader: any DashboardDataSource
    /// The concrete fake beside the protocol member — an existential cannot
    /// witness `device` typed `any DeviceReadings`, so the scripted fields a
    /// test flips mid-run live here and the run asks through the getter.
    let deviceReadings: FakeDeviceReadings
    var device: any DeviceReadings { deviceReadings }

    /// The scripted value behind `bridgeReady`; every read is counted so a
    /// test can pin "the run consults the transport once per question" —
    /// the consult itself is the only observable part of the log it feeds.
    var scriptedBridgeReady = false
    private(set) var bridgeReadyReads = 0
    var bridgeReady: Bool {
        bridgeReadyReads += 1
        return scriptedBridgeReady
    }

    init(
        nodeState: NodeState, reader: any DashboardDataSource,
        device: FakeDeviceReadings = FakeDeviceReadings()
    ) {
        self.nodeState = nodeState
        self.reader = reader
        self.deviceReadings = device
    }

    func startNode(
        arguments: [String], torSession: UUID?, torSocksPort: UInt16?
    ) -> Bool {
        startNodeArguments = arguments
        // A successful start moves the node toward `.starting` — leaving the
        // state at `.stopped` would read as "stopped mid-run" to the wait's
        // still-wanted check and end the run early.
        if startNodeResult { nodeState = .starting }
        return startNodeResult
    }

    @discardableResult
    func startTorIfStillEnabled(reading defaults: UserDefaults) -> Bool {
        torStartCalls += 1
        return torStillEnabled
    }
}

#endif
