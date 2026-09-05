//
//  NodeAutomationTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import Testing
@testable import NodeApp

// MARK: - Which step an unattended run takes

@Test func leavesAloneANodeItDidNotStart() {
    // ADR 0005: an automation firing during a session someone is watching must not
    // stop the node they are looking at.
    #expect(NodeAutomation.step(nodeIsStopped: false, privacyEnabled: false, privacyReady: false)
            == .reportExistingNode)
    #expect(NodeAutomation.step(nodeIsStopped: false, privacyEnabled: true, privacyReady: true)
            == .reportExistingNode)
}

@Test func spendsTheWindowEstablishingThePrivateNetworkWhenItIsNotReady() {
    #expect(NodeAutomation.step(nodeIsStopped: true, privacyEnabled: true, privacyReady: false)
            == .waitForPrivateNetwork)
}

@Test func startsWhenThePrivateNetworkIsReady() {
    #expect(NodeAutomation.step(nodeIsStopped: true, privacyEnabled: true, privacyReady: true)
            == .startNode)
}

@Test func startsWhenThePrivacySettingIsOff() {
    #expect(NodeAutomation.step(nodeIsStopped: true, privacyEnabled: false, privacyReady: false)
            == .startNode)
}

// MARK: - The argument guard (ADR 0006)

@Test func refusesToBuildArgumentsWithThePrivacySettingOnAndNoProxy() {
    // Without this, a wait that exited for any reason would fall through into a
    // direct connection, exposing the person's home network address to peers.
    var builderRan = false
    #expect(throws: NodeAutomation.StartRefusal.privateNetworkNotReady) {
        try NodeAutomation.startArguments(privacyEnabled: true, proxyAddress: nil) { _ in
            builderRan = true
            return []
        }
    }
    #expect(builderRan == false, "the builder must not run at all, not merely have its output discarded")
}

@Test func buildsWithTheProxyWhenOneExists() throws {
    let args = try NodeAutomation.startArguments(
        privacyEnabled: true, proxyAddress: "127.0.0.1:9050"
    ) { proxy in ["-proxy=\(proxy ?? "none")"] }
    #expect(args == ["-proxy=127.0.0.1:9050"])
}

@Test func buildsWithoutAProxyWhenThePrivacySettingIsOff() throws {
    let args = try NodeAutomation.startArguments(
        privacyEnabled: false, proxyAddress: nil
    ) { proxy in ["-proxy=\(proxy ?? "none")"] }
    #expect(args == ["-proxy=none"])
}

// MARK: - The deadline leaves room to shut down

@Test func holdWindowLeavesRoomForShutdownInsideTheAllowedTime() {
    // A background-triggered action gets roughly 30 seconds. Shutdown is not instant:
    // it sends a stop command and waits for the daemon's main function to return.
    let total = NodeAutomation.holdWindow + NodeAutomation.shutdownReserve
    #expect(total < .seconds(30))
    #expect(NodeAutomation.shutdownReserve > .zero)
}
