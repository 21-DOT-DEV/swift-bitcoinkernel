//
//  SyncNodeLongRunningIntentTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import Synchronization
import Testing
@testable import NodeApp

// The task group underneath the long-running action exists only on iOS, and
// builds only under the iOS 27 SDK toolchain (Xcode 27+) like the action
// itself. Each test carries @available(iOS 27.0, *) so an older runtime
// reports it as skipped rather than passing without exercising anything — the
// supported form, per the testing library's docs. The suite type itself stays
// always-available because the macros generate registration code
// unconditionally.
//
// The work the group wraps is injected, so these tests drive the group's real
// semantics — first-yield-wins, the heartbeat's nil cancelling the work child,
// the stop flag crossing into a @MainActor child — with no node, no session,
// and no four-minute wait.
#if os(iOS)

@Suite("Long-running action heartbeat group")
@MainActor
struct SyncNodeLongRunningIntentTests {
    @available(iOS 27.0, *)
    private func makeMeter() -> (Progress, ProgressMeter) {
        let progress = Progress()
        return (progress, ProgressMeter(
            progress: progress, scale: SyncNodeLongRunningIntent.scale))
    }

    @available(iOS 27.0, *)
    private func report(_ outcome: NodeRunOutcome, _ summary: String) -> NodeRunReport {
        NodeRunReport(
            outcome: outcome, chain: "main", blockHeight: 42, summary: summary)
    }

    @available(iOS 27.0, *)
    @Test("the work's report is the group's answer when it finishes first")
    func workReportWins() async {
        let (_, meter) = makeMeter()
        let report = await SyncNodeLongRunningIntent.runWithHeartbeat(
            meter: meter,
            isStopped: { false },
            heartbeatInterval: .milliseconds(10)
        ) { _ in
            self.report(.alreadyRunning, "from work")
        }
        #expect(report.outcome == .alreadyRunning)
        #expect(report.summary == "from work")
    }

    @available(iOS 27.0, *)
    @Test("a run already stopped yields the no-answer report, not the work's")
    func stoppedYieldsNoAnswer() async {
        let (_, meter) = makeMeter()
        let report = await SyncNodeLongRunningIntent.runWithHeartbeat(
            meter: meter,
            isStopped: { true },
            heartbeatInterval: .milliseconds(10)
        ) { _ in
            // Five seconds is still hundreds of heartbeat ticks of "still
            // running" — and bounds the failure mode: if the group's cancelAll
            // stopped reaching the work child, the group would await this sleep
            // in full before the expectation below could fail.
            try? await Task.sleep(for: .seconds(5))
            return self.report(.started, "from work")
        }
        #expect(report.outcome == .noAnswer)
    }

    @available(iOS 27.0, *)
    @Test("the heartbeat's nil is what cancels the work child")
    func heartbeatEndCancelsWork() async {
        // The API promises `onCancel` runs, not that the work's task is the
        // thing cancelled — so the group unwinds the work itself. This is the
        // behaviour the isStopped plumbing exists to provide: the flag flips
        // once the work is running, the heartbeat's nil ends the group, and
        // the work child must observe cancellation rather than running on.
        let (_, meter) = makeMeter()
        let begun = Mutex(false)
        let observedCancel = Mutex(false)
        let report = await SyncNodeLongRunningIntent.runWithHeartbeat(
            meter: meter,
            isStopped: { begun.withLock { $0 } },
            heartbeatInterval: .milliseconds(20)
        ) { _ in
            begun.withLock { $0 = true }
            // Bounded on purpose: if the heartbeat's nil stopped cancelling the
            // work child, an unbounded wait here would hang the test rather
            // than fail it — this loop gives the regression ~5s to show up.
            for _ in 0 ..< 1_000 where !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(5))
            }
            observedCancel.withLock { $0 = true }
            return self.report(.started, "from work")
        }
        #expect(observedCancel.withLock { $0 })
        #expect(report.outcome == .noAnswer)
    }

    @available(iOS 27.0, *)
    @Test("the heartbeat budget outlasts the longest designed wait")
    func heartbeatCoverageExceedsWait() {
        // Three constants in two files decide how long the run can go quiet
        // before the card stops moving: the heartbeat interval, the meter's
        // half-bar budget, and the wait this action is allowed. Count the
        // budget by ticking the real meter dry rather than duplicating its
        // scale/2 formula here, then require the product to outlast the wait.
        //
        // This models the dominant silent stretch, not the whole run: a run
        // can also go quiet inside `readConditions` (≤2 s) before the wait and
        // inside `measuredReport`'s last question (≤ `questionBudget`) after —
        // tail time this bound does not see. In practice the milestones inside
        // `NodeRun` write real reports that cover ticks the model counts as
        // silent, which is where the slack comes from. `questionBudget` stays
        // private to NodeRun — if it ever grows, revisit whether this guard
        // still bounds the right thing.
        let (progress, meter) = makeMeter()
        var ticks = 0
        while true {
            let before = progress.completedUnitCount
            meter.tick()
            if progress.completedUnitCount == before { break }
            ticks += 1
        }
        let coverage = ticks * Int(SyncNodeLongRunningIntent.heartbeat.components.seconds)
        #expect(coverage >= Int(SyncNodeLongRunningIntent.waitForFirstAnswer.components.seconds))
    }
}

#endif
