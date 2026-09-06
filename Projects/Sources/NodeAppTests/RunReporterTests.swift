//
//  RunReporterTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
@testable import NodeApp

// The wording is the whole product here: an unattended run is invisible except for
// this sentence, so it is tested rather than left to the reporter that renders it.
// Runs on the macOS leg too, which is why RunOutcome carries no ActivityKit or
// UserNotifications types.

@Suite("Run outcome messages")
struct RunOutcomeTests {

    @Test func aRefusalSaysWhatWasRefusedAndWhy() {
        // ADR 0006: an unattended run never starts on a direct connection. Nobody sees
        // a dialog at 3am, so this sentence is the only place the refusal lands.
        let message = RunOutcome.refusedPrivateNetworkUnavailable.message
        #expect(message.contains("private network"))
        #expect(message.contains("did not start"))
    }

    @Test func anAdoptedNodeSaysItWasLeftAlone() {
        // ADR 0005: only stop a node this action started.
        let message = RunOutcome.adopted(height: 554_355).message
        #expect(message.contains("554355") || message.contains("554,355"))
        #expect(message.lowercased().contains("left"))
    }

    @Test func acompletedRunStatesTheGainAsAFloor() {
        // The node keeps downloading through shutdown and the height is read before
        // it, so a bare number would understate the run. Matches the dialog wording.
        let message = RunOutcome.completed(
            height: 554_355, blocksGained: 20, connections: 3
        ).message
        #expect(message.contains("at least"))
        #expect(message.contains("20"))
    }

    @Test func aRunThatGainedNothingWithNoPeersSaysSo() {
        // Two runs in three currently gain nothing because no peer connects in time.
        // A report that hides this looks like a broken node rather than a short window.
        let message = RunOutcome.completed(
            height: 554_355, blocksGained: 0, connections: 0
        ).message
        #expect(message.lowercased().contains("no connections"))
    }

    @Test func aRunThatGainedNothingDespitePeersDoesNotBlameTheNetwork() {
        let message = RunOutcome.completed(
            height: 554_355, blocksGained: 0, connections: 4
        ).message
        #expect(!message.lowercased().contains("no connections"))
    }

    @Test func anUnmeasuredGainIsNotReportedAsZero() {
        let message = RunOutcome.completed(
            height: 554_355, blocksGained: nil, connections: 1
        ).message
        #expect(!message.contains("at least"))
    }

    @Test func aFailureCarriesItsReasonVerbatim() {
        let message = RunOutcome.failed(reason: "node never reported ready").message
        #expect(message.contains("node never reported ready"))
    }

    @Test func everyOutcomeProducesANonEmptyMessage() {
        // A reporter that posts an empty notification is worse than one that posts
        // nothing, so no case may fall through to "".
        let all: [RunOutcome] = [
            .refusedPrivateNetworkUnavailable,
            .adopted(height: 1),
            .completed(height: 1, blocksGained: nil, connections: nil),
            .failed(reason: "x")
        ]
        for outcome in all { #expect(!outcome.message.isEmpty) }
    }
}

/// Stands in for a reporter that fails at every opportunity. Declared at file scope
/// rather than nested in the suite, where the conformance does not resolve.
private struct HostileReporter: RunReporter {
    func begin(startHeight: Int?, deadline: ContinuousClock.Instant) async {}
    func finish(_ outcome: RunOutcome) async {}
}

@Suite("Reporting never breaks a run")
struct RunReporterContractTests {

    @Test func theProtocolOffersNoWayToFailARun() async {
        // Not a behavioural test — a shape test. `begin` and `finish` are async and
        // non-throwing by design, so a reporting failure cannot propagate into the
        // sync. If either ever gains `throws`, this stops compiling.
        let reporter: any RunReporter = HostileReporter()
        await reporter.begin(startHeight: nil, deadline: .now)
        await reporter.finish(.failed(reason: "ignored"))
    }

    @Test func theNoOpReporterIsTheMacOSDefault() async {
        let reporter = NoOpReporter()
        await reporter.begin(startHeight: 1, deadline: .now)
        await reporter.finish(.adopted(height: 1))
    }
}
