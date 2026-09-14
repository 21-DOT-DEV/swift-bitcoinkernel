//
//  NodeRunReportTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import AppIntents
import Testing
@testable import NodeApp

// The types under test exist only in phone and tablet builds — the same
// compile-time gate as `NodeRunReport.swift` itself, so this whole suite is
// empty on a Mac build.
#if os(iOS)

@Suite("Node run report")
struct NodeRunReportTests {

    @Test("every outcome has display wording")
    func everyOutcomeHasDisplayWording() {
        // `caseDisplayRepresentations` is a plain dictionary, so nothing checks it
        // for completeness when the code builds — a missing entry is a crash at the
        // moment that outcome is shown, not a build failure. This is the check the
        // type cannot make for itself.
        for outcome in NodeRunOutcome.allCases {
            #expect(NodeRunOutcome.caseDisplayRepresentations[outcome] != nil)
        }
    }

    @Test("the text stored behind each outcome is pinned")
    func outcomeTextIsPinned() {
        // A person's saved automation compares against these strings. Each is
        // assigned explicitly so renaming a case cannot silently change it — and
        // this test freezes the assignment, so changing one is a deliberate act
        // rather than a side effect of a rename.
        #expect(NodeRunOutcome.started.rawValue == "started")
        #expect(NodeRunOutcome.alreadyRunning.rawValue == "alreadyRunning")
        #expect(NodeRunOutcome.declined.rawValue == "declined")
        #expect(NodeRunOutcome.didNotComeUp.rawValue == "didNotComeUp")
    }

    @Test("every plain outcome survives the round trip through the Shortcuts-facing type")
    func outcomeRoundTrips() {
        // The two outcome types cannot be one: the Shortcuts-facing one needs plain
        // text behind each case, which Swift forbids alongside attached data. The
        // failure this guards is a crossed mapping — a conversion that swapped two
        // cases would compile and then report the wrong ending.
        let outcomes: [NodeAutomation.Outcome] = [
            .started, .alreadyRunning, .declined, .didNotComeUp,
        ]
        for outcome in outcomes {
            #expect(NodeRunOutcome(outcome).plain == outcome)
        }
    }
}

#endif
