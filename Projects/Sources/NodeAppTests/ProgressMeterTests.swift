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

// ProgressMeter exists only where the long-running action does — it is declared
// inside SyncNodeLongRunningIntent.swift's own fences, so this file carries the
// same pair: iOS only, and only under the iOS 27 SDK toolchain. Availability is
// checked inside each test rather than on the suite: @Suite/@Test cannot be
// applied to @available-gated declarations (the macros generate registration
// code that must exist unconditionally).
#if os(iOS) && compiler(>=6.4)

@Suite("Progress card meter")
@MainActor
struct ProgressMeterTests {
    @available(iOS 27.0, *)
    private func makeMeter() -> (Progress, ProgressMeter) {
        let progress = Progress()
        return (progress, ProgressMeter(progress: progress, scale: 100))
    }

    @Test("a lower real report never moves the bar backwards")
    func barNeverRetreats() {
        guard #available(iOS 27.0, *) else { return }
        // The heartbeat can tick past where the real work has reached; when the
        // run then reports an honest lower figure, the card must not retreat.
        let (progress, meter) = makeMeter()
        meter.advance(to: 0.5)
        meter.advance(to: 0.2)
        #expect(progress.completedUnitCount == 50)
    }

    @Test("the heartbeat adds one notch and no more")
    func heartbeatTicksOneStep() {
        guard #available(iOS 27.0, *) else { return }
        let (progress, meter) = makeMeter()
        meter.tick()
        meter.tick()
        #expect(progress.completedUnitCount == 2)
    }

    @Test("nothing but the end of the run fills the bar")
    func barStopsShortOfFull() {
        guard #available(iOS 27.0, *) else { return }
        // A full bar is a claim that the work finished — so not even a real
        // report of 1.0 may reach it.
        let (progress, meter) = makeMeter()
        meter.advance(to: 1.0)
        for _ in 0 ..< 200 { meter.tick() }
        #expect(progress.completedUnitCount == 99)
    }

    @Test("heartbeats alone never carry the bar past halfway")
    func heartbeatStopsAtHalfway() {
        guard #available(iOS 27.0, *) else { return }
        // A bar that crept to nearly full during a silent wait would claim the
        // run is almost done when it may barely have started — the tick's reach
        // is capped so "still working" can never read as "nearly finished".
        let (progress, meter) = makeMeter()
        for _ in 0 ..< 200 { meter.tick() }
        #expect(progress.completedUnitCount == 50)
    }

    @Test("a run that read a node finishes with a full bar")
    func earnedFinishFills() {
        guard #available(iOS 27.0, *) else { return }
        let (progress, meter) = makeMeter()
        meter.advance(to: 0.4)
        meter.finish(NodeAutomation.ending(outcome: .started, summary: "read 42 blocks"))
        #expect(progress.completedUnitCount == 100)
        #expect(progress.localizedAdditionalDescription == "read 42 blocks")
    }

    @Test("a refused run ends short of full, with its ending written")
    func unearnedFinishStaysShort() {
        guard #available(iOS 27.0, *) else { return }
        let (progress, meter) = makeMeter()
        meter.advance(to: 0.4)
        meter.finish(
            NodeAutomation.ending(outcome: .declined, summary: "Low Power Mode is on."))
        #expect(progress.completedUnitCount == 40)
        #expect(progress.localizedDescription.isEmpty == false)
        #expect(progress.localizedAdditionalDescription == "Low Power Mode is on.")
    }
}

#endif
