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
            outcome: .started, syncResult: .notMeasured,
            chain: "main", blockHeight: 900_000, blocksGainedThisRun: nil,
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

    // MARK: - Sync result vocabulary

    @Test("every sync result has display wording")
    func everySyncResultHasDisplayWording() {
        // `caseDisplayRepresentations` is a plain dictionary, so nothing checks
        // it for completeness when the code builds — a missing entry is a crash
        // at the moment that result is shown, not a build failure.
        for result in NodeSyncResult.allCases {
            #expect(NodeSyncResult.caseDisplayRepresentations[result] != nil)
        }
    }

    @Test("the text stored behind each sync result is pinned")
    func syncResultTextIsPinned() {
        // A person's saved automation compares against these strings. Each is
        // assigned explicitly so renaming a case cannot silently change it —
        // and this test freezes the assignment. Cases may be appended (the raw
        // values persist by string); renaming or renumbering is a breaking
        // change to automations already built.
        #expect(NodeSyncResult.caughtUp.rawValue == "caughtUp")
        #expect(NodeSyncResult.stillSyncing.rawValue == "stillSyncing")
        #expect(NodeSyncResult.noProgress.rawValue == "noProgress")
        #expect(NodeSyncResult.nodeStopped.rawValue == "nodeStopped")
        #expect(NodeSyncResult.conditionsChanged.rawValue == "conditionsChanged")
        #expect(NodeSyncResult.notMeasured.rawValue == "notMeasured")
    }

    @Test("every sync result's displayed wording is pinned")
    func syncResultWordingIsPinned() {
        // What the Shortcuts picker shows for each case — a commitment beside
        // the raw values, so the exact wording is frozen here too. A literal
        // behind `DisplayRepresentation` resolves through the catalog in the
        // development language, so `String(localized:)` reads back the wording
        // a person sees.
        let expected: [NodeSyncResult: String] = [
            .caughtUp: "Caught up",
            .stillSyncing: "Still syncing",
            .noProgress: "No progress",
            .nodeStopped: "Node stopped",
            .conditionsChanged: "Conditions changed",
            .notMeasured: "Not measured",
        ]
        for result in NodeSyncResult.allCases {
            guard let expectedWording = expected[result] else {
                Issue.record("a case with no pinned wording: \(result)")
                continue
            }
            let title = NodeSyncResult.caseDisplayRepresentations[result]?.title
            #expect(title != nil)
            if let title {
                #expect(String(localized: title) == expectedWording)
            }
        }
    }

    @MainActor
    @Test("a run with no sync answer reports notMeasured and no gain count")
    func unmeasuredSyncReportsNotMeasured() {
        // The `notMeasured` rules (FR-005): a run that ended before the watch —
        // declined, or never answered — has no sync verdict to give, and the
        // count is absent rather than zero: `nil` is the field's own way of
        // saying nobody watched — the same "absent means not measured" rule
        // every other number on the report follows.
        let declined = NodeRunReport(
            outcome: .declined, syncResult: .notMeasured,
            chain: nil, blockHeight: nil, blocksGainedThisRun: nil,
            dialogTemplate: "The node did not start.")
        #expect(declined.syncResult == .notMeasured)
        #expect(declined.blocksGainedThisRun == nil)
        // The same standing answer through a real producer path.
        let noAnswer = NodeRun.noAnswerReport()
        #expect(noAnswer.syncResult == .notMeasured)
        #expect(noAnswer.blocksGainedThisRun == nil)
        // Zero is a claim of its own — "watched, and nothing arrived" — which
        // must never read the same as an unwatched run's absent count.
        let watchedZero = NodeRunReport(
            outcome: .alreadyRunning, syncResult: .noProgress,
            chain: "signet", blockHeight: 910, blocksGainedThisRun: 0,
            dialogTemplate: "A node was already running.")
        #expect(watchedZero.blocksGainedThisRun == 0)
    }

    @Test("the two block counters measure different spans")
    func blockCountersMeasureDifferentSpans() {
        // FR-016: `blocksSinceLastCheck` spans the gap before this run — the
        // pre-run baseline — while `blocksGainedThisRun` counts only what this
        // run watched arrive. A watch that found the node mid-recovery reports
        // both honestly: ten since the last check, three while watching.
        let report = NodeRunReport(
            outcome: .alreadyRunning, syncResult: .stillSyncing,
            chain: "signet", blockHeight: 910,
            blocksSinceLastCheck: 10, blocksGainedThisRun: 3,
            dialogTemplate: "A node was already running.")
        #expect(report.syncResult == .stillSyncing)
        #expect(report.blocksSinceLastCheck == 10)
        #expect(report.blocksGainedThisRun == 3)
    }
}

#endif
