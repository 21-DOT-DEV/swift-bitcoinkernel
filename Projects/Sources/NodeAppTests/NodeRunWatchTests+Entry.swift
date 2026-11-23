//
//  NodeRunWatchTests+Entry.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Bitcoin
import Foundation
import Synchronization
import Testing
@testable import NodeApp

// `NodeRun` and `NodeRunReport` exist only in phone and tablet builds — the
// same compile-time gate as the sources, so this whole suite is empty on a
// Mac build.
#if os(iOS)

/// The entry phase — the run baseline it pins, the weigh-in
/// gate that admits or declines the watch, and the gate's own
/// stop/cancel precedence — before the watch opens at all.
extension NodeRunWatchTests {

    /// The baseline stores a mid-flight overwrite can move — the
    /// run-owned `last_run_*` a sibling run's returned result writes, and
    /// the observational `last_known_*` the sync poll rewrites every
    /// ~30 s, which a first-ever run still reads as its fallback.
    enum BaselineStore {
        case run, known

        /// Writes this leg's store — the seed before the run attaches,
        /// the overwrite while its first question is in flight.
        /// `@MainActor` like the persist helpers it wraps — a nested type
        /// does not inherit the suite's isolation.
        @MainActor
        func persist(height: Int, in defaults: UserDefaults) {
            switch self {
            case .run:
                NodeViewModel.persistLastRun(
                    height: height, chain: "signet", in: defaults)
            case .known:
                NodeViewModel.persistLastKnown(
                    height: height, chain: "signet", in: defaults)
            }
        }

        /// What the store holds now — proof the overwrite landed.
        @MainActor
        func persistedHeight(in defaults: UserDefaults) -> Int? {
            switch self {
            case .run: NodeViewModel.lastRun(in: defaults)?.height
            case .known: NodeViewModel.lastKnown(in: defaults)?.height
            }
        }
    }
    /// `previous` is pinned at attach — before the already-running
    /// path's first question — so a baseline that moves while that
    /// question is in flight cannot shrink the delta the report counts
    /// (FR-017). The parked answer holds the exact window: the ask can
    /// sit unanswered up to `questionBound`, and inside it a sibling
    /// run's returned result moves `last_run_*` — or, on a first-ever
    /// run, the poll moves the `last_known_*` fallback.
    @Test(
        "a baseline moved inside the first question still measures from attach",
        .timeLimit(.minutes(1)),
        arguments: [BaselineStore.run, .known])
    func baselinePinnedAtAttach(store: BaselineStore) async throws {
        let clock = watchClock()
        let defaults = makeVolatileDefaults(distinguisher: "\(store)")
        // The tip the last check stood behind when the run attaches.
        store.persist(height: 90, in: defaults)
        let answerParked = Gate()
        let releaseAnswer = Gate()
        let committed = Gate()
        let calls = Mutex(0)
        let session = FakeRunSession(
            nodeState: .running,
            reader: StagedReader(
                blockchain: {
                    let n = calls.withLock { n in n += 1; return n }
                    if n == 1 {
                        // The entry question parks mid-flight — the window
                        // between attach and the weigh-in a baseline read
                        // *after* the answer would see the overwrite in.
                        answerParked.open()
                        try await releaseAnswer.wait()
                        return try decodeWatchInfo()
                    }
                    // One banked gain, then flat: the watch earns a real
                    // figure and ends on the 60 s budget, under every leash.
                    return try decodeWatchInfo(blocks: 110, headers: 200)
                },
                network: { try decodeNetworkInfo() }))
        let done = Gate()
        let run = ClockSubject.$isCurrent.withValue(true) {
            Task { @MainActor in
                // `answerParked`/`committed` are awaited below. Abandoned
                // if the run ends first, so the awaits fail by name instead
                // of wedging to `.timeLimit`.
                defer {
                    answerParked.abandon(); committed.abandon(); done.open()
                }
                return await NodeRun.perform(
                    session: session, waitForFirstAnswer: .seconds(240),
                    syncBudget: .seconds(60),
                    clock: clock.clock, now: { watchNow }, defaults: defaults) {
                    if $0.headline != nil { committed.open() }
                }
            }
        }
        defer { run.cancel() }
        // No drive to reach the parked question — the first ask issues
        // without any clock advance.
        try await answerParked.wait()
        // The overwrite lands while the entry answer is in flight — a
        // sibling run's result moving `last_run_*`, or the poll moving
        // `last_known_*`: the tip *that* check saw.
        store.persist(height: 105, in: defaults)
        releaseAnswer.open()
        // The commit's headline proves the released answer landed and the
        // weigh-in passed.
        try await committed.wait()
        try await clock.test.drive(untilDone: done)
        let report = await run.value

        #expect(report.syncEnding == .stillSyncing)
        #expect(report.outcome == .alreadyRunning)
        // Measured from the attach-time 90 — a baseline read after the
        // answer would start at the overwritten 105 and report 5.
        #expect(report.blocksSinceLastCheck == 20)
        // The run's own watch baseline is untouched: the watch banked
        // 100 → 110 on its first pass.
        #expect(report.blockHeight == 110)
        #expect(report.blocksGainedThisRun == 10)
        // The overwrite genuinely landed — the store holds 105, so the
        // pinned baseline is the only reason the delta reads 20.
        #expect(store.persistedHeight(in: defaults) == 105)
    }
    /// The run-owned store wins whenever both answer: the delta is "since
    /// the last check", not "since the last poll" — a poll that ran in the
    /// last thirty seconds must not collapse it.
    @Test("a populated run baseline outranks the poll's newer tip")
    func prefersRunBaselineOverPoll() async throws {
        let clock = watchClock()
        let defaults = makeVolatileDefaults()
        NodeViewModel.persistLastRun(height: 90, chain: "signet", in: defaults)
        NodeViewModel.persistLastKnown(height: 105, chain: "signet", in: defaults)
        let session = FakeRunSession(
            nodeState: .running,
            reader: StagedReader(
                blockchain: { try decodeWatchInfo(blocks: 110) },
                network: { try decodeNetworkInfo() }))
        // Unbudgeted: one question, then `measuredReport` — no watch needed
        // to expose which store `lastRunBaseline` consulted.
        let report = await NodeRun.perform(
            session: session, waitForFirstAnswer: .seconds(240),
            clock: clock.clock, now: { watchNow }, defaults: defaults
        ) { _ in }
        // 110 − 90 = 20 measures from the run baseline; preferring the
        // poll's 105 would have read 5.
        #expect(report.blocksSinceLastCheck == 20)
        #expect(report.outcome == .alreadyRunning)
    }
    /// A reading that would have declined the gate — flag clear, gap
    /// closed, tip fresh — ends `caughtUp`, not `alreadyAtTip`, when it
    /// arrives mid-watch: the gate is consulted once, on the entry
    /// reading, and never again (FR-001).
    @Test("a decline-shaped reading mid-watch still ends caughtUp", .timeLimit(.minutes(1)))
    func gateIsConsultedOnce() async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults()
        let calls = Mutex(0)
        let session = FakeRunSession(
            nodeState: .running,
            reader: StagedReader(
                blockchain: {
                    let n = calls.withLock { n in n += 1; return n }
                    return n == 1
                        ? try decodeWatchInfo(blocks: 100, headers: 200)
                        : try decodeWatchInfo(
                            blocks: 200, headers: 200, ibd: false,
                            tip: watchNow.timeIntervalSince1970)
                },
                network: { try decodeNetworkInfo() }))
        let done = Gate()
        let run = ClockSubject.$isCurrent.withValue(true) {
            Task { @MainActor in
                defer { done.open() }
                return await NodeRun.perform(
                    session: session, waitForFirstAnswer: .seconds(240),
                    syncBudget: .seconds(600),
                    clock: clock.clock, now: { watchNow }, defaults: store)
            }
        }
        try await clock.test.drive(untilDone: done)
        let report = await run.value

        #expect(report.syncEnding == .caughtUp)
        #expect(report.blocksGainedThisRun == 100)
    }
    /// A first answer that already proves the tip — flag clear, gap
    /// closed, tip fresh — declines the gate on the spot: the run reports
    /// `alreadyAtTip`, asks `getblockchaininfo` only the once (no watch
    /// polls, so nothing is claimed gained), and writes no watch card.
    @Test("a node already at the tip declines the gate — alreadyAtTip, no watch", .timeLimit(.minutes(1)))
    func gateDeclineEndsAlreadyAtTip() async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults()
        let calls = Mutex(0)
        var emitted: [NodeRun.ProgressUpdate] = []
        let session = FakeRunSession(
            nodeState: .running,
            reader: StagedReader(
                blockchain: {
                    calls.withLock { $0 += 1 }
                    return try decodeWatchInfo(
                        blocks: 200, headers: 200, ibd: false,
                        tip: watchNow.timeIntervalSince1970)
                },
                network: { try decodeNetworkInfo() }))
        let done = Gate()
        let run = Task { @MainActor in
            defer { done.open() }
            return await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                syncBudget: .seconds(600),
                clock: clock.clock, now: { watchNow }, defaults: store) {
                emitted.append($0)
            }
        }
        defer { run.cancel() }
        // No drive: a declined gate ends the run on the spot — every
        // question answers immediately, so nothing is owed the clock.
        try await done.wait()
        let report = await run.value

        #expect(report.syncEnding == .alreadyAtTip)
        #expect(report.syncResult == .caughtUp)
        #expect(report.blocksGainedThisRun == nil)
        #expect(calls.withLock { $0 } == 1)
        #expect(emitted.allSatisfy { $0.headline == nil })
        // And none of them claimed the bar's end: no watch committed, so
        // every write stays strictly inside the start-up band — a
        // closing `fraction: 1` folded to the ceiling is the only
        // emission that would break it.
        #expect(emitted.allSatisfy { $0.fraction < NodeAutomation.startUpBandEnd })
    }
    /// A self-defined chain declines the gate as `notMeasured` — "still
    /// syncing" is ill-defined on regtest, so nothing is claimed rather
    /// than something vacuous (FR-015).
    @Test("a self-defined chain declines the gate as notMeasured", .timeLimit(.minutes(1)))
    func gateDeclineEndsNotMeasured() async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults()
        let calls = Mutex(0)
        let session = FakeRunSession(
            nodeState: .running,
            reader: StagedReader(
                blockchain: {
                    calls.withLock { $0 += 1 }
                    // The flag is even set — a just-started regtest can
                    // sit there — and the gate must still decline.
                    return try decodeWatchInfo(chain: "regtest")
                },
                network: { try decodeNetworkInfo() }))
        let done = Gate()
        let run = Task { @MainActor in
            defer { done.open() }
            return await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                syncBudget: .seconds(600),
                clock: clock.clock, now: { watchNow }, defaults: store)
        }
        defer { run.cancel() }
        // No drive: a declined gate ends the run on the spot — every
        // question answers immediately, so nothing is owed the clock.
        try await done.wait()
        let report = await run.value

        #expect(report.syncEnding == .notMeasured)
        #expect(report.syncResult == .notMeasured)
        #expect(report.blocksGainedThisRun == nil)
        #expect(calls.withLock { $0 } == 1)
    }
    /// Both paths that skipped preflight — reading a node already
    /// running and waiting on one already starting — owe the entry
    /// weigh-in once before the watch commits: a refusal ends
    /// `watchRefused` naming the condition, the gather ran exactly once,
    /// and the watch never began (FR-012).
    @Test(
        "a weigh-in refusal ends watchRefused before the watch commits",
        .timeLimit(.minutes(1)),
        arguments: [NodeState.running, .starting])
    func weighInRefusalEndsWatchRefused(nodeState: NodeState) async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults(distinguisher: nodeState.rawValue)
        let device = FakeDeviceReadings(firstNetworkReport: {
            NetworkCost(isMetered: true, isDataRestricted: false)
        })
        let calls = Mutex(0)
        var emitted: [NodeRun.ProgressUpdate] = []
        let session = FakeRunSession(
            nodeState: nodeState,
            reader: StagedReader(
                blockchain: {
                    calls.withLock { $0 += 1 }
                    return try decodeWatchInfo()
                },
                network: { try decodeNetworkInfo() }),
            device: device)
        let run = Task { @MainActor in
            await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                syncBudget: .seconds(600),
                clock: clock.clock, now: { watchNow }, defaults: store) {
                emitted.append($0)
            }
        }
        // No drive: the refusal path parks on zero clock sleeps — the
        // first question, the gather, and `measuredReport` all answer on
        // the spot — so `run.value` completes on real scheduling while
        // the weigh-in's 2 s bound sits parked at virtual t=2, a deadline
        // nobody advances the clock to. Nor can the answer lose the other
        // arm: `withHardTimeout` drops a work reply stamped at or past
        // the deadline, and `finishedAt` reads this same frozen `now` —
        // the stamp is t=0 no matter how starved the runner. A watch
        // that wrongly committed would nap instead — the handler below
        // cancels the run out from under the await a `.timeLimit` cancel
        // can't resume itself: the nap throws, the run unwinds to
        // `noAnswer`, and the regression reads as a wrong ending, not a
        // hang that leaks the parked task.
        let report = await withTaskCancellationHandler {
            await run.value
        } onCancel: {
            run.cancel()
        }

        #expect(report.syncEnding == .watchRefused(.meteredNetwork))
        #expect(report.syncResult == .conditionsChanged)
        #expect(report.outcome == .alreadyRunning)
        // Nobody watched — the run's gain field stays absent (FR-016).
        #expect(report.blocksGainedThisRun == nil)
        // The weigh-in ran exactly once — `networkFirst` has no other
        // caller on the preflight-skipped paths — and its narrow gather
        // never spent the filesystem reads `readConditions` would.
        let deviceCalls = device.calls.withLock { $0 }
        #expect(deviceCalls.filter { $0 == "networkFirst" }.count == 1)
        #expect(!deviceCalls.contains("protectedDataAvailable"))
        #expect(!deviceCalls.contains("prepareChainFolder"))
        // The watch never committed: the entry read is the only
        // `getblockchaininfo`, and no write carried the syncing headline.
        #expect(calls.withLock { $0 } == 1)
        #expect(emitted.allSatisfy { $0.headline == nil })
        // Nor did any claim the bar's end — the refusal's writes all
        // stay strictly inside the start-up band.
        #expect(emitted.allSatisfy { $0.fraction < NodeAutomation.startUpBandEnd })
    }
    /// The start path already weighed conditions at preflight, so the
    /// weigh-in never runs there — a link turning metered between that
    /// weigh and the first answer is nobody's to re-read at commit, and
    /// the flipped report is a tripwire, not a stimulus: an unconditional
    /// weigh-in would refuse on it. FR-011's "already on at commit is
    /// accepted" is only reachable because this path skips the weigh-in.
    @Test(
        "the start path skips the weigh-in — a condition turning mid-start still commits",
        .timeLimit(.minutes(1)))
    func startPathSkipsWeighIn() async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults()
        let networkReportCalls = Mutex(0)
        let device = FakeDeviceReadings(firstNetworkReport: {
            // Cheap for the preflight gather, metered for whatever asks
            // next — the weigh-in would refuse on it, so its not running
            // is what this test proves.
            NetworkCost(
                isMetered: networkReportCalls.withLock { n in
                    n += 1
                    return n > 1
                },
                isDataRestricted: false)
        })
        var emitted: [NodeRun.ProgressUpdate] = []
        let session = FakeRunSession(
            nodeState: .stopped,
            reader: StagedReader(
                blockchain: { try decodeWatchInfo() },
                network: { try decodeNetworkInfo() }),
            device: device)
        session.startNodeResult = true
        let done = Gate()
        let run = ClockSubject.$isCurrent.withValue(true) {
            Task { @MainActor in
                defer { done.open() }
                return await NodeRun.perform(
                    session: session, waitForFirstAnswer: .seconds(240),
                    syncBudget: .seconds(60),
                    clock: clock.clock, now: { watchNow }, defaults: store) {
                    emitted.append($0)
                }
            }
        }
        try await clock.test.drive(untilDone: done)
        let report = await run.value

        // The watch committed and spent its budget — the flipped report
        // was never re-read, so no refusal could fire.
        #expect(report.syncEnding == .stillSyncing)
        // `networkFirst` answered exactly once — the preflight gather. A
        // second call would be the weigh-in this path skips.
        let deviceCalls = device.calls.withLock { $0 }
        #expect(deviceCalls.filter { $0 == "networkFirst" }.count == 1)
        // The commit write landed: a pass carried the syncing headline.
        #expect(emitted.contains { $0.headline != nil })
    }
    /// The fallback owes no second weigh either: `startNode` refusing
    /// means the node moved off `.stopped` on its own — someone else
    /// started it — and the `.startNode` step's `readConditions` already
    /// ran moments earlier, so the wait lands on the watch with the same
    /// `false` the direct start carries.
    @Test(
        "the start-fallback path also skips the weigh-in — preflight already ran",
        .timeLimit(.minutes(1)))
    func startFallbackSkipsWeighIn() async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults()
        let networkReportCalls = Mutex(0)
        let device = FakeDeviceReadings(firstNetworkReport: {
            // Cheap for the preflight gather, metered for whatever asks
            // next — a weigh-in on this path would refuse on it.
            NetworkCost(
                isMetered: networkReportCalls.withLock { n in
                    n += 1
                    return n > 1
                },
                isDataRestricted: false)
        })
        var emitted: [NodeRun.ProgressUpdate] = []
        let session = FakeRunSession(
            nodeState: .stopped,
            reader: StagedReader(
                blockchain: { try decodeWatchInfo() },
                network: { try decodeNetworkInfo() }),
            device: device)
        // `startNode` declines with the node already `.starting` — the
        // "moved off stopped" case the fallback exists for.
        session.startNodeDeclinedState = .starting
        let done = Gate()
        let run = ClockSubject.$isCurrent.withValue(true) {
            Task { @MainActor in
                defer { done.open() }
                return await NodeRun.perform(
                    session: session, waitForFirstAnswer: .seconds(240),
                    syncBudget: .seconds(60),
                    clock: clock.clock, now: { watchNow }, defaults: store) {
                    emitted.append($0)
                }
            }
        }
        try await clock.test.drive(untilDone: done)
        let report = await run.value

        #expect(report.syncEnding == .stillSyncing)
        // One `networkFirst` — the step's own `readConditions`. A second
        // would be a weigh-in nobody owes.
        let deviceCalls = device.calls.withLock { $0 }
        #expect(deviceCalls.filter { $0 == "networkFirst" }.count == 1)
        #expect(emitted.contains { $0.headline != nil })
    }
    /// A stop landing inside the weigh-in's network wait outranks the
    /// refusal the gather was about to return — the deliberate action
    /// beats the conditions verdict (FR-019) — so the run falls through
    /// to the first pass and ends `nodeStopped`, never `watchRefused`.
    @Test(
        "a stop inside the weigh-in's gather ends nodeStopped, not watchRefused",
        .timeLimit(.minutes(1)))
    func stopDuringWeighInEndsNodeStopped() async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults()
        let gatherParked = Gate()
        let releaseReport = Gate()
        let device = FakeDeviceReadings(firstNetworkReport: {
            gatherParked.open()
            await releaseReport.waitIgnoringCancellation()
            return NetworkCost(isMetered: true, isDataRestricted: false)
        })
        var emitted: [NodeRun.ProgressUpdate] = []
        let session = FakeRunSession(
            nodeState: .running,
            reader: StagedReader(
                blockchain: { try decodeWatchInfo() },
                network: { try decodeNetworkInfo() }),
            device: device)
        let done = Gate()
        let run = Task { @MainActor in
            defer { done.open() }
            return await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                syncBudget: .seconds(600),
                clock: clock.clock, now: { watchNow }, defaults: store) {
                emitted.append($0)
            }
        }
        defer { run.cancel() }
        // The gather is parked inside its network wait; the stop lands
        // while the report is in flight.
        try await gatherParked.wait()
        session.nodeState = .stopping
        releaseReport.open()
        // No drive: the released gather, the fall-through commit, and
        // the stopped first pass all resolve on the spot — nothing is
        // owed the clock, so no armed bound can outrun the answer.
        try await done.wait()
        let report = await run.value

        #expect(report.syncEnding == .nodeStopped)
        #expect(report.outcome == .alreadyRunning)
        // The refusal was dropped, so the fall-through committed the
        // watch — a `watchingTitle` write landed before the stop's pass.
        // The flash is T022's per-pass liveness write, not the weigh-in's
        // call: every pass writes the watch headline, ending or not.
        #expect(emitted.contains { $0.headline != nil })
    }
    /// A cancellation inside the weigh-in's network wait discards the
    /// gather with it — the verdict it parked is moot, and the run
    /// reports `noAnswer` rather than either watch ending.
    @Test(
        "a cancel inside the weigh-in's gather reports noAnswer",
        .timeLimit(.minutes(1)))
    func cancelDuringWeighInReportsNoAnswer() async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults()
        let gatherParked = Gate()
        let releaseReport = Gate()
        let device = FakeDeviceReadings(firstNetworkReport: {
            gatherParked.open()
            await releaseReport.waitIgnoringCancellation()
            return NetworkCost(isMetered: true, isDataRestricted: false)
        })
        let session = FakeRunSession(
            nodeState: .running,
            reader: StagedReader(
                blockchain: { try decodeWatchInfo() },
                network: { try decodeNetworkInfo() }),
            device: device)
        let done = Gate()
        let run = Task { @MainActor in
            defer { done.open() }
            return await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                syncBudget: .seconds(600),
                clock: clock.clock, now: { watchNow }, defaults: store)
        }
        defer { run.cancel() }
        // The run ends while the gather's report is parked; the verdict
        // it finally returns is nobody's business.
        try await gatherParked.wait()
        run.cancel()
        releaseReport.open()
        // No drive: the cancel already released the gather's bound — the
        // release only frees the parked fake — and `noAnswer` resolves
        // on the spot.
        try await done.wait()
        let report = await run.value

        #expect(report.outcome == .noAnswer)
        #expect(report.syncEnding == .notMeasured)
    }

}

#endif
