//
//  NodeRunWatchTests.swift
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

/// The watch stage's wired shape: every pass asks one bounded question,
/// feeds the state, applies the ending precedence, and writes fresh
/// progress — a run that judges answers, never the `.running` flag.
@Suite("Sync watch")
@MainActor
struct NodeRunWatchTests {

    /// A node still `.starting` reaches `caughtUp` entirely on its
    /// answers — the run never consults the `.running` flag — while every
    /// pass lands a fresh write inside the watch band.
    @Test("an advancing node is watched to caughtUp on answers alone", .timeLimit(.minutes(1)))
    func advancesToCaughtUp() async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults()
        let calls = Mutex(0)
        let session = FakeRunSession(
            nodeState: .starting,
            reader: StagedReader(
                blockchain: {
                    let n = calls.withLock { n in n += 1; return n }
                    switch n {
                    case 1: return try decodeWatchInfo(blocks: 100, headers: 200)
                    case 2: return try decodeWatchInfo(blocks: 110, headers: 200)
                    case 3: return try decodeWatchInfo(blocks: 140, headers: 200)
                    // The flag clears and headers land one step past the
                    // entry figure — the headersAdvanced leg, on a tip
                    // still stale, so no other leg can have fired.
                    default: return try decodeWatchInfo(
                        blocks: 210, headers: 210, ibd: false)
                    }
                },
                network: { try decodeNetworkInfo() }))
        var emitted: [NodeRun.ProgressUpdate] = []
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
        try await clock.questionArmed.wait()
        try await clock.test.drive(untilDone: done, by: .seconds(5))
        let report = await run.value

        #expect(report.syncEnding == .caughtUp)
        #expect(report.outcome == .alreadyRunning)
        #expect(report.blocksGainedThisRun == 110)
        // Every pass wrote: the entry write plus one per question — the
        // node never saw `.running`, so only its answers moved the watch.
        let watchWrites = emitted.filter { $0.headline != nil }
        #expect(watchWrites.count == 4)
        let fractions = watchWrites.map(\.fraction)
        #expect(fractions == fractions.sorted())
        #expect(
            fractions.allSatisfy {
                $0 >= NodeAutomation.watchBand(0)
                    && $0 <= NodeAutomation.watchBandEnd
            })
    }

    /// The 30 s question bound covers the first-answer wait's questions
    /// and the watch's alike — a slow-but-alive node the 10 s bound would
    /// write off still reaches the watch — and the ~5 s nap cadences it.
    @Test("every budgeted question carries the wider bound", .timeLimit(.minutes(1)))
    func questionBoundWidens() async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults()
        let session = FakeRunSession(
            nodeState: .stopped,
            reader: StagedReader(
                // Always the same still-syncing answer: the run crosses
                // the start path's first-answer wait into the watch,
                // where flat answers hold until the budget spends.
                blockchain: { try decodeWatchInfo() },
                network: { try decodeNetworkInfo() }))
        session.startNodeResult = true
        let done = Gate()
        let run = Task { @MainActor in
            defer { done.open() }
            return await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                syncBudget: .seconds(60),
                clock: clock.clock, now: { watchNow }, defaults: store)
        }
        try await clock.questionArmed.wait()
        try await clock.test.drive(untilDone: done, by: .seconds(5))
        let report = await run.value

        let requests = clock.log.durations.withLock { $0 }
        // At least two ~30 s armings: one inside `awaitFirstAnswer`, one
        // inside the watch — under the 10 s bound none could exceed 10.
        #expect(requests.filter { $0 > .seconds(20) }.count >= 2)
        // The cadence nap between watch passes.
        #expect(requests.contains {
            $0 > .seconds(4) && $0 <= .seconds(5)
        })
        #expect(report.syncEnding == .stillSyncing)
        #expect(report.blocksGainedThisRun == 0)
    }

    /// A deliberate stop outranks whatever the pass proved — here a fresh
    /// answer parked mid-flight lands after the stop and is discarded —
    /// and still reports on the measured report rather than a blanked
    /// `noAnswer`: `nodeStopped` is itself an ending (FR-008).
    @Test("a node stopped mid-watch ends nodeStopped, answer in flight discarded", .timeLimit(.minutes(1)))
    func stoppedMidWatchEndsNodeStopped() async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults()
        let secondAsk = Gate()
        let releaseAnswer = Gate()
        let calls = Mutex(0)
        let session = FakeRunSession(
            nodeState: .running,
            reader: StagedReader(
                blockchain: {
                    let n = calls.withLock { n in n += 1; return n }
                    if n == 1 { return try decodeWatchInfo() }
                    // The second question — the watch's first — parks its
                    // answer until the stop has landed, so the pass can
                    // only reach its post-ask re-read already stopped.
                    secondAsk.open()
                    try await releaseAnswer.wait()
                    return try decodeWatchInfo(blocks: 150, headers: 200)
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
        try await clock.questionArmed.wait()
        try await clock.test.drive(untilDone: secondAsk, by: .seconds(5))
        // The answer is in flight; the stop lands while it is.
        session.nodeState = .stopping
        releaseAnswer.open()
        try await clock.test.drive(untilDone: done, by: .seconds(5))
        let report = await run.value

        #expect(report.syncEnding == .nodeStopped)
        #expect(report.outcome == .alreadyRunning)
        // The discarded answer earned nothing — the gain is still the
        // pre-stop zero, not the 150 the answer carried.
        #expect(report.blocksGainedThisRun == 0)
    }

    /// `Task.isCancelled` is consulted separately from the stop flag —
    /// a cancel landing while a poll question is in flight discards even
    /// the answer that arrives afterward: the measured watch report is
    /// thrown away for a blank `noAnswer`, the one path in the run that
    /// spends a committed watch on nothing.
    @Test("a run cancelled mid-watch discards the measured report", .timeLimit(.minutes(1)))
    func cancelledMidWatchReportsNoAnswer() async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults()
        let pollIssued = Gate()
        let releaseAnswer = Gate()
        let calls = Mutex(0)
        let session = FakeRunSession(
            nodeState: .running,
            reader: StagedReader(
                blockchain: {
                    let n = calls.withLock { n in n += 1; return n }
                    if n == 1 { return try decodeWatchInfo() }
                    // The watch's first poll parks its answer until the
                    // cancel has landed — `waitIgnoringCancellation`,
                    // because the question runs inside the cancelled
                    // task and its answer must still arrive: only then
                    // does the post-ask check do the discarding.
                    pollIssued.open()
                    await releaseAnswer.waitIgnoringCancellation()
                    return try decodeWatchInfo(blocks: 150, headers: 200)
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
        try await clock.questionArmed.wait()
        try await clock.test.drive(untilDone: pollIssued, by: .seconds(5))
        run.cancel()
        releaseAnswer.open()
        try await clock.test.drive(untilDone: done, by: .seconds(5))
        let report = await run.value

        #expect(report.outcome == .noAnswer)
        #expect(report.syncEnding == .notMeasured)
        #expect(report.blocksGainedThisRun == nil)
        // The cancel provably landed while the watch's own question was
        // in flight — the poll was issued, its answer never counted.
        #expect(calls.withLock { $0 } == 2)
    }

    /// A tripped leash and a spent budget standing on the same pass ends
    /// `noProgress` — the verdict outranks the bound, per the precedence
    /// `watchEnding` is the single owner of.
    @Test("a tripped leash on the spent-budget pass ends noProgress", .timeLimit(.minutes(1)))
    func leashOutranksSpentBudget() async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults()
        let calls = Mutex(0)
        let session = FakeRunSession(
            nodeState: .running,
            reader: StagedReader(
                blockchain: {
                    if calls.withLock({ n in n += 1; return n }) == 1 {
                        return try decodeWatchInfo()
                    }
                    throw StagedReader.NotScripted()
                },
                network: { try decodeNetworkInfo() }))
        let done = Gate()
        let run = Task { @MainActor in
            defer { done.open() }
            return await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                // Exactly the unproductive leash: the pass at t=120 holds
                // both the tripped leash and the spent budget.
                syncBudget: .seconds(120),
                clock: clock.clock, now: { watchNow }, defaults: store)
        }
        try await clock.questionArmed.wait()
        try await clock.test.drive(untilDone: done, by: .seconds(5))
        let report = await run.value

        guard case .noProgress = report.syncEnding else {
            Issue.record("expected noProgress, got \(report.syncEnding)")
            return
        }
        #expect(report.blocksGainedThisRun == 0)
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
        let run = Task { @MainActor in
            defer { done.open() }
            return await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                syncBudget: .seconds(600),
                clock: clock.clock, now: { watchNow }, defaults: store)
        }
        try await clock.questionArmed.wait()
        try await clock.test.drive(untilDone: done, by: .seconds(5))
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
        try await clock.questionArmed.wait()
        try await clock.test.drive(untilDone: done, by: .seconds(5))
        let report = await run.value

        #expect(report.syncEnding == .alreadyAtTip)
        #expect(report.syncResult == .caughtUp)
        #expect(report.blocksGainedThisRun == nil)
        #expect(calls.withLock { $0 } == 1)
        #expect(emitted.allSatisfy { $0.headline == nil })
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
        try await clock.questionArmed.wait()
        try await clock.test.drive(untilDone: done, by: .seconds(5))
        let report = await run.value

        #expect(report.syncEnding == .notMeasured)
        #expect(report.syncResult == .notMeasured)
        #expect(report.blocksGainedThisRun == nil)
        #expect(calls.withLock { $0 } == 1)
    }

    /// The same watch-worthy first answer on an unbudgeted run reports
    /// exactly as the short action always has — `notMeasured`, nothing
    /// counted, one question asked at the 10 s bound — the watch budget
    /// changes nothing it is absent from.
    @Test("an unbudgeted run reports notMeasured and asks once", .timeLimit(.minutes(1)))
    func unbudgetedRunUnchanged() async throws {
        let test = ManualClock()
        let durations = Mutex<[Duration]>([])
        let observed = ObservedClock(base: test) { deadline, _ in
            durations.withLock { $0.append(test.now.duration(to: deadline)) }
        }
        let store = makeVolatileDefaults()
        let calls = Mutex(0)
        let session = FakeRunSession(
            nodeState: .running,
            reader: StagedReader(
                blockchain: {
                    calls.withLock { $0 += 1 }
                    return try decodeWatchInfo()
                },
                network: { try decodeNetworkInfo() }))
        let report = await NodeRun.perform(
            session: session, waitForFirstAnswer: .seconds(240),
            clock: observed, now: { watchNow }, defaults: store)

        #expect(report.syncEnding == .notMeasured)
        #expect(report.blocksGainedThisRun == nil)
        // One `getblockchaininfo`, one `getnetworkinfo` — no watch polls.
        #expect(calls.withLock { $0 } == 1)
        #expect(durations.withLock { $0 }.allSatisfy { $0 <= .seconds(10) })
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
        let run = Task { @MainActor in
            defer { done.open() }
            return await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                syncBudget: .seconds(60),
                clock: clock.clock, now: { watchNow }, defaults: store) {
                emitted.append($0)
            }
        }
        try await clock.questionArmed.wait()
        try await clock.test.drive(untilDone: done, by: .seconds(5))
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
        let run = Task { @MainActor in
            defer { done.open() }
            return await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                syncBudget: .seconds(60),
                clock: clock.clock, now: { watchNow }, defaults: store) {
                emitted.append($0)
            }
        }
        try await clock.questionArmed.wait()
        try await clock.test.drive(untilDone: done, by: .seconds(5))
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
        try await clock.questionArmed.wait()
        // The gather is parked inside its network wait; the stop lands
        // while the report is in flight.
        try await gatherParked.wait()
        session.nodeState = .stopping
        releaseReport.open()
        try await clock.test.drive(untilDone: done, by: .seconds(5))
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
        try await clock.questionArmed.wait()
        // The run ends while the gather's report is parked; the verdict
        // it finally returns is nobody's business.
        try await gatherParked.wait()
        run.cancel()
        releaseReport.open()
        try await clock.test.drive(untilDone: done, by: .seconds(5))
        let report = await run.value

        #expect(report.outcome == .noAnswer)
        #expect(report.syncEnding == .notMeasured)
    }
}

#endif
