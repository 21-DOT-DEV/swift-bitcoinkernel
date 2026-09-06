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

    @Test func acompletedRunReportsProgressSinceTheLastCheck() {
        // Not blocks gained during the action, which is now always about zero: the
        // action returns as soon as the node answers and the node carries on
        // downloading for minutes afterwards. Measuring from the last recorded height
        // captures that, and it is the only figure that shows the feature working.
        let message = RunOutcome.completed(height: 570_926, blocksSinceLastCheck: 2_145).message
        #expect(message.contains("2145") || message.contains("2,145"))
        #expect(message.lowercased().contains("since"))
    }

    @Test func noProgressSinceTheLastCheckIsSaidPlainly() {
        let message = RunOutcome.completed(height: 570_926, blocksSinceLastCheck: 0).message
        #expect(message.lowercased().contains("no new blocks"))
    }

    @Test func anUnmeasurableGainIsNotReportedAsZero() {
        // Never having recorded a height is a different statement from having
        // recorded one and found it unchanged.
        let message = RunOutcome.completed(height: 570_926, blocksSinceLastCheck: nil).message
        #expect(!message.lowercased().contains("no new blocks"))
        #expect(message.contains("570926") || message.contains("570,926"))
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
            .completed(height: 1, blocksSinceLastCheck: nil),
            .failed(reason: "x")
        ]
        for outcome in all { #expect(!outcome.message.isEmpty) }
    }
}

#if os(iOS)
@Suite("The Shortcuts list stays in step with the fuller one")
struct OutcomeDerivationTests {

    @Test func eachSituationMapsToItsShortcutsEquivalent() {
        // The value of deriving is not this test — it is that adding a new case to
        // RunOutcome stops the app compiling until the mapping accounts for it.
        #expect(NodeRunOutcome(.adopted(height: 1)) == .alreadyRunning)
        #expect(NodeRunOutcome(.refusedPrivateNetworkUnavailable) == .waitingOnPrivateNetwork)
        #expect(NodeRunOutcome(.failed(reason: "x")) == .couldNotStart)
        #expect(NodeRunOutcome(.completed(height: 1, blocksSinceLastCheck: nil)) == .startedAndRan)
    }
}
#endif
