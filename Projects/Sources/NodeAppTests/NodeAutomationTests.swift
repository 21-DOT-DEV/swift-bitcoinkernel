//
//  NodeAutomationTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Bitcoin
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


// MARK: - The budget leaves room to shut down

@Test func workStopsEarlyEnoughForShutdownToFitTheBudget() {
    let start = ContinuousClock.now
    let deadline = NodeAutomation.workDeadline(from: start)
    let untilDeadline = start.duration(to: deadline)
    // Shutdown was measured at 4.5 seconds on device; it must fit after the deadline.
    #expect(untilDeadline + NodeAutomation.shutdownReserve == NodeAutomation.budget)
    #expect(NodeAutomation.shutdownReserve >= .seconds(5))
}

// MARK: - Time actually running, which is the only interval blocks can arrive in

@Test func countsOnlyTheTimeTheNodeWasRunning() {
    let ready = ContinuousClock.now
    let stopped = ready.advanced(by: .seconds(7))
    #expect(abs(NodeAutomation.secondsRunning(readyAt: ready, stoppedAt: stopped) - 7) < 0.05)
}

@Test func reportsZeroRatherThanNegativeWhenTheOrderIsReversed() {
    let ready = ContinuousClock.now
    #expect(NodeAutomation.secondsRunning(readyAt: ready, stoppedAt: ready.advanced(by: .seconds(-3))) == 0)
}

// MARK: - The live reading, taken through the seam the app already defines

private func chainInfo(_ json: String) throws -> BlockchainInfo {
    try JSONDecoder().decode(BlockchainInfo.self, from: Data(json.utf8))
}

@Test func readsChainHeightAndHowFarBehindFromOneReading() throws {
    // Far behind: 100 validated against 200 known headers.
    let info = try chainInfo("""
    {
      "chain": "signet", "blocks": 100, "headers": 200,
      "bestblockhash": "0000000000000000000000000000000000000000000000000000000000000abc",
      "difficulty": 1.0, "time": 1713300000, "mediantime": 1713299990,
      "verificationprogress": 0.5, "initialblockdownload": true,
      "chainwork": "0000000000000000000000000000000000000000000000000000000000000abc",
      "size_on_disk": 1000, "pruned": false, "warnings": []
    }
    """)
    let reading = NodeAutomation.reading(from: info)
    #expect(reading.chain == "signet")
    #expect(reading.height == 100)
    // Without this figure a height of 100 reads as "caught up" when it is not.
    #expect(reading.blocksBehind == 100)
}

@Test func reportsNothingBehindWhenTheNodeIsAtTheFront() throws {
    let info = try chainInfo("""
    {
      "chain": "main", "blocks": 876000, "headers": 876000,
      "bestblockhash": "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f",
      "difficulty": 110568145977.78, "time": 1713300000, "mediantime": 1713299000,
      "verificationprogress": 0.999999, "initialblockdownload": false,
      "chainwork": "00000000000000000000000000000000000000009c8e007a3e19b3e0b28a5c07",
      "size_on_disk": 12345678901, "pruned": true, "pruneheight": 800000,
      "automatic_pruning": true, "prune_target_size": 1073741824, "warnings": []
    }
    """)
    let reading = NodeAutomation.reading(from: info)
    #expect(reading.chain == "main")
    #expect(reading.blocksBehind == 0)
}

// MARK: - Blocks gained during a run

@Test func measuresTheBlocksGainedAcrossARun() {
    let start = NodeAutomation.LiveReading(chain: "main", height: 876_000, blocksBehind: 45)
    let end = NodeAutomation.LiveReading(chain: "main", height: 876_045, blocksBehind: 0)
    #expect(NodeAutomation.blocksGained(from: start, to: end) == 45)
}

@Test func reportsZeroGainRatherThanNothingWhenTheHeightDidNotMove() {
    let reading = NodeAutomation.LiveReading(chain: "main", height: 876_000, blocksBehind: 12)
    // A measured zero and an unmeasurable gain mean different things: the first says
    // the run achieved nothing, the second says nobody looked.
    #expect(NodeAutomation.blocksGained(from: reading, to: reading) == 0)
}

@Test func cannotMeasureAGainWithoutBothEnds() {
    let reading = NodeAutomation.LiveReading(chain: "main", height: 876_000, blocksBehind: 0)
    #expect(NodeAutomation.blocksGained(from: nil, to: reading) == nil)
    #expect(NodeAutomation.blocksGained(from: reading, to: nil) == nil)
}

@Test func refusesToSubtractHeightsFromDifferentChains() {
    // Switching networks mid-run would otherwise report a gain of hundreds of
    // thousands of blocks, or a negative one.
    let start = NodeAutomation.LiveReading(chain: "signet", height: 100, blocksBehind: 0)
    let end = NodeAutomation.LiveReading(chain: "main", height: 876_000, blocksBehind: 0)
    #expect(NodeAutomation.blocksGained(from: start, to: end) == nil)
}

@Test func neverReportsANegativeGainIfTheHeightGoesBackwards() {
    // A chain reorganisation can lower the height. "Gained -3 blocks" is not a thing
    // a person should be shown.
    let start = NodeAutomation.LiveReading(chain: "main", height: 876_003, blocksBehind: 0)
    let end = NodeAutomation.LiveReading(chain: "main", height: 876_000, blocksBehind: 0)
    #expect(NodeAutomation.blocksGained(from: start, to: end) == 0)
}

// MARK: - The measured window

@Test func stopsWorkFarEnoughAheadOfTheMeasuredCutoff() {
    // Two device runs logged the system's out-of-time warning at 27.4 and 27.9
    // seconds, and the slowest observed shutdown took 4.8. Work must therefore stop
    // by 21 seconds so even a worst-case shutdown lands before the warning.
    #expect(NodeAutomation.budget == .seconds(27))
    let start = ContinuousClock.now
    #expect(NodeAutomation.workDeadline(from: start) == start.advanced(by: .seconds(21)))
}

// MARK: - Shutdown against its reserve

@Test func flagsAShutdownThatOutranTheTimeHeldBackForIt() {
    // Measured shutdowns climbed 0.34 → 5.10 s across four device runs against a
    // 6 s reserve. Nobody knows yet whether that levels off, so the run reports
    // when it overruns rather than trying to predict it.
    #expect(NodeAutomation.shutdownOverran(.seconds(7)))
    #expect(!NodeAutomation.shutdownOverran(.milliseconds(5_100)))
    // Exactly using the reserve is not an overrun.
    #expect(!NodeAutomation.shutdownOverran(NodeAutomation.shutdownReserve))
}

// MARK: - Whether to ask the node to stop at all

@Test func onlyStopsANodeThatGotFarEnoughToAnswer() {
    // A node that never answered is still inside its own start-up, where a stop
    // cannot be serviced — and the wait for it cannot be interrupted (ADR 0007).
    // Asking anyway hung a device run until Shortcuts killed it, which the person
    // saw as "Sync Bitcoin Node timeout".
    #expect(!NodeAutomation.shouldRequestShutdown(nodeAnswered: false, askedToStop: true))
}

@Test func leavesTheNodeRunningUnlessAskedToStopIt() {
    // The action's own time is capped at about 27 seconds, but the node it starts
    // keeps running far longer — measured at 8 to 15 minutes — and that is when
    // blocks actually arrive. Stopping at the end of the action threw all of it
    // away: one device run stopped a healthy node after 6 seconds having made no
    // connections at all.
    #expect(!NodeAutomation.shouldRequestShutdown(nodeAnswered: true, askedToStop: false))
    #expect(NodeAutomation.shouldRequestShutdown(nodeAnswered: true, askedToStop: true))
}

@Test func beingAskedToStopCannotOverrideANodeThatNeverAnswered() {
    // The switch is a preference; the hang it would cause is not negotiable.
    #expect(!NodeAutomation.shouldRequestShutdown(nodeAnswered: false, askedToStop: true))
}
