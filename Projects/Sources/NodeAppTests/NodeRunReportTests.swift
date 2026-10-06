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
        #expect(NodeRunOutcome.noAnswer.rawValue == "noAnswer")
    }

    @Test("every plain outcome survives the round trip through the Shortcuts-facing type")
    func outcomeRoundTrips() {
        // The two outcome types cannot be one: the Shortcuts-facing one needs plain
        // text behind each case, which Swift forbids alongside attached data. The
        // failure this guards is a crossed mapping — a conversion that swapped two
        // cases would compile and then report the wrong ending.
        let outcomes: [NodeAutomation.Outcome] = [
            .started, .alreadyRunning, .declined, .didNotComeUp, .noAnswer,
        ]
        for outcome in outcomes {
            #expect(NodeRunOutcome(outcome).plain == outcome)
        }
    }

    @Test("the report's sentence is resolved from its template — one source, two renderings")
    func summaryDerivesFromTemplate() {
        // The actions hand `dialogText` to `IntentDialog` for the system's own
        // rendering, while `summary` is the resolved `String` a following
        // automation step compares against — both must read the same words.
        let report = NodeRunReport(
            outcome: .started, chain: "main", blockHeight: 900_000,
            dialogTemplate: "Node running on Mainnet at block \(900_000).")
        // The height is resolved through the device's locale, so the expected
        // figure comes from formatted() — pinning "900,000" verbatim would fail
        // on a simulator grouping digits differently.
        #expect(report.summary == "Node running on Mainnet at block \(900_000.formatted()).")
        #expect(report.dialogTemplate != nil)
        #expect(String(localized: report.dialogText) == report.summary)
    }

    @Test("a report built by the AppIntents machinery still shows its sentence in the dialog")
    func dialogTextFallsBackToSummary() {
        // `init()` is the path the framework itself takes when a report crosses
        // the process boundary, which drops `dialogTemplate`. The dialog must
        // still show the sentence — the fallback wraps the already-resolved
        // summary as an argument (a `%@` template), never as a lookup key.
        var report = NodeRunReport()
        report.outcome = .started
        report.summary = "Low Power Mode is on, so the node did not start."
        #expect(String(localized: report.dialogText) == report.summary)
        // A sentence that passes verbatim can't tell the two mechanisms
        // apart — a lookup that misses renders the key text itself, so a
        // regression to `LocalizedStringResource(stringLiteral:)` would stay
        // green. A summary equal to an existing catalog key discriminates:
        // as an argument it renders verbatim, but as a key it hits
        // `run.report.rendered-summary` (value `"%@"`) and comes back as the
        // template, not the sentence.
        report.summary = "run.report.rendered-summary"
        #expect(String(localized: report.dialogText) == report.summary)
    }
}

#endif
