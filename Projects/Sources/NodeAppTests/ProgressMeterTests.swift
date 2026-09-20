//
//  ProgressMeterTests.swift
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

// ProgressMeter exists only where the long-running action does — iOS only, and
// the file builds only under the iOS 27 SDK toolchain (Xcode 27+), the demo
// apps' declared minimum. Each test then carries @available(iOS 27.0, *) so an
// older runtime reports it as skipped rather than passing without exercising
// anything — the supported form, per the testing library's docs. The suite
// type itself stays always-available because the macros generate registration
// code unconditionally.
#if os(iOS)

@Suite("Progress card meter")
@MainActor
struct ProgressMeterTests {
    @available(iOS 27.0, *)
    private func makeMeter() -> (Progress, ProgressMeter) {
        let progress = Progress()
        return (progress, ProgressMeter(progress: progress, scale: 100))
    }

    @available(iOS 27.0, *)
    @Test("a lower real report never moves the bar backwards")
    func barNeverRetreats() {
        // The heartbeat can tick past where the real work has reached; when the
        // run then reports an honest lower figure, the card must not retreat.
        let (progress, meter) = makeMeter()
        meter.advance(to: 0.5)
        meter.advance(to: 0.2)
        #expect(progress.completedUnitCount == 50)
    }

    @available(iOS 27.0, *)
    @Test("the heartbeat adds one notch and no more")
    func heartbeatTicksOneStep() {
        let (progress, meter) = makeMeter()
        meter.tick()
        meter.tick()
        #expect(progress.completedUnitCount == 2)
    }

    @available(iOS 27.0, *)
    @Test("a fresh real report stands in for the next heartbeat")
    func realReportCoversNextTick() {
        // The heartbeat exists to cover silence: when a real report just wrote,
        // the tick that follows has nothing to add and spends no budget.
        let (progress, meter) = makeMeter()
        meter.advance(to: 0.3)
        meter.tick()
        #expect(progress.completedUnitCount == 30)
        meter.tick()
        #expect(progress.completedUnitCount == 31)
    }

    @available(iOS 27.0, *)
    @Test("the heartbeat still moves the bar after real progress passes halfway")
    func heartbeatKeepsWritingPastHalfway() {
        // The keep-alive cannot go dead in the back half of a run: once the
        // fresh-report tick has been skipped, the next tick must write a new
        // value again — the only thing the system is documented to watch.
        let (progress, meter) = makeMeter()
        meter.advance(to: 0.6)
        meter.tick()
        #expect(progress.completedUnitCount == 60)
        meter.tick()
        #expect(progress.completedUnitCount == 61)
        meter.tick()
        #expect(progress.completedUnitCount == 62)
    }

    @available(iOS 27.0, *)
    @Test("the heartbeat budget is spent on silence, not on real reports")
    func budgetSpentOnSilenceOnly() {
        // Sixty real reports with a tick after each: every tick is covered, so
        // the full budget is still available when silence actually arrives —
        // and even spending it all, the bar cannot be carried past full.
        let (progress, meter) = makeMeter()
        for i in 1 ... 60 {
            meter.advance(to: Double(i) / 100)
            meter.tick()
        }
        #expect(progress.completedUnitCount == 60)
        for _ in 0 ..< 60 { meter.tick() }
        #expect(progress.completedUnitCount == 99)
    }

    @available(iOS 27.0, *)
    @Test("nothing but the end of the run fills the bar")
    func barStopsShortOfFull() {
        // A full bar is a claim that the work finished — so not even a real
        // report of 1.0 may reach it.
        let (progress, meter) = makeMeter()
        meter.advance(to: 1.0)
        for _ in 0 ..< 200 { meter.tick() }
        #expect(progress.completedUnitCount == 99)
    }

    @available(iOS 27.0, *)
    @Test("heartbeats alone never carry the bar past halfway")
    func heartbeatStopsAtHalfway() {
        // A bar that crept to nearly full during a silent wait would claim the
        // run is almost done when it may barely have started — the heartbeat's
        // total contribution is capped so "still working" can never read as
        // "nearly finished".
        let (progress, meter) = makeMeter()
        for _ in 0 ..< 200 { meter.tick() }
        #expect(progress.completedUnitCount == 50)
    }

    @available(iOS 27.0, *)
    @Test("a run that read a node finishes with a full bar")
    func earnedFinishFills() {
        let (progress, meter) = makeMeter()
        meter.advance(to: 0.4)
        meter.finish(NodeAutomation.ending(outcome: .started, summary: "read 42 blocks"))
        #expect(progress.completedUnitCount == 100)
        #expect(progress.localizedAdditionalDescription == "read 42 blocks")
    }

    @available(iOS 27.0, *)
    @Test("a refused run ends short of full, with its ending written")
    func unearnedFinishStaysShort() {
        let (progress, meter) = makeMeter()
        meter.advance(to: 0.4)
        meter.finish(
            NodeAutomation.ending(outcome: .declined, summary: "Low Power Mode is on."))
        #expect(progress.completedUnitCount == 40)
        #expect(progress.localizedDescription.isEmpty == false)
        #expect(progress.localizedAdditionalDescription == "Low Power Mode is on.")
    }

    @available(iOS 27.0, *)
    @Test("a run the system ended says so, without filling the bar")
    func timedOutEndingWrittenWithoutFill() {
        let (progress, meter) = makeMeter()
        meter.advance(to: 0.4)
        meter.finish(NodeAutomation.timedOutEnding)
        #expect(progress.completedUnitCount == 40)
        #expect(progress.localizedDescription == "Run cut short")
        #expect(progress.localizedAdditionalDescription.isEmpty == false)
    }

    @available(iOS 27.0, *)
    @Test("nothing moves the bar backwards after the run ended")
    func barNeverRetreatsAfterFinish() {
        // `finish` reports full directly; a late write after it must still be
        // unable to drag the bar back — the rule is structural, not call order.
        let (progress, meter) = makeMeter()
        meter.tick()
        meter.finish(NodeAutomation.ending(outcome: .started, summary: "done"))
        meter.tick()
        #expect(progress.completedUnitCount == 100)
    }

    @available(iOS 27.0, *)
    @Test("a nonsense report is ignored rather than trapping")
    func nonFiniteReportIgnored() {
        let (progress, meter) = makeMeter()
        meter.advance(to: .nan)
        meter.advance(to: .infinity)
        #expect(progress.completedUnitCount == 0)
    }

    @available(iOS 27.0, *)
    @Test("a huge finite report clamps to the bar instead of trapping")
    func hugeFiniteReportClamped() {
        // `Int64(_:)` traps on out-of-range values, finite or not — the clamp to
        // 0...1 must run before the conversion, so 1e300 reads as "done" rather
        // than crashing the action.
        let (progress, meter) = makeMeter()
        meter.advance(to: 1e300)
        meter.advance(to: -1e300)
        #expect(progress.completedUnitCount == 99)
    }

    @available(iOS 27.0, *)
    @Test("a real report that changes nothing does not cover the next heartbeat")
    func repeatedRealReportDoesNotSuppressHeartbeat() {
        // The wait loop reports the same 0.9 every half second for the last
        // ~24 seconds of a maximum-length wait. Those writes are not new
        // values, so they must not stand in for heartbeat ticks — the run is
        // exactly as silent as if nothing had been reported at all.
        let (progress, meter) = makeMeter()
        meter.advance(to: 0.9)
        meter.tick()
        #expect(progress.completedUnitCount == 90)
        for _ in 0 ..< 4 {
            meter.advance(to: 0.9)
            meter.tick()
        }
        #expect(progress.completedUnitCount == 94)
    }
}

#endif
