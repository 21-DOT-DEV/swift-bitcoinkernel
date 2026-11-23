//
//  NodeRunWatchTests+Lifecycle.swift
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

/// The running watch — mid-watch stops, cancels, drift, and the
/// leash and ending precedence that decide how a pass counts.
extension NodeRunWatchTests {

    /// A deliberate stop outranks whatever the pass proved — here a fresh
    /// answer parked mid-flight lands after the stop and is discarded —
    /// and still reports on the measured report rather than a blanked
    /// `noAnswer`: `nodeStopped` is itself an ending (FR-008). The closing
    /// peer count is spent nowhere — a stopped node is never asked — so
    /// `connections` reads absent rather than carrying a dead figure.
    @Test("a node stopped mid-watch ends nodeStopped, answer in flight discarded", .timeLimit(.minutes(1)))
    func stoppedMidWatchEndsNodeStopped() async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults()
        let secondAsk = Gate()
        let releaseAnswer = Gate()
        let calls = Mutex(0)
        let networkCalls = Mutex(0)
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
                network: {
                    networkCalls.withLock { $0 += 1 }
                    return try decodeNetworkInfo()
                }))
        let done = Gate()
        let run = Task { @MainActor in
            // `secondAsk` is awaited below. Abandoned if the run ends
            // first, so the await fails by name instead of wedging to
            // `.timeLimit`.
            defer { secondAsk.abandon(); done.open() }
            return await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                syncBudget: .seconds(600),
                clock: clock.clock, now: { watchNow }, defaults: store)
        }
        defer { run.cancel() }
        // No drive: the first pass asks without any clock advance — the
        // gate, not a hop, proves the answer is parked mid-flight.
        try await secondAsk.wait()
        // The answer is in flight; the stop lands while it is.
        session.nodeState = .stopping
        releaseAnswer.open()
        // The released answer, the stopped pass, and the measured report
        // all resolve on the spot — nothing owed the clock, so no armed
        // bound can outrun the delivery it bounds.
        try await done.wait()
        let report = await run.value

        #expect(report.syncEnding == .nodeStopped)
        #expect(report.syncResult == .nodeStopped)
        #expect(report.outcome == .alreadyRunning)
        // The discarded answer earned nothing — the gain is still the
        // pre-stop zero, not the 150 the answer carried.
        #expect(report.blocksGainedThisRun == 0)
        // The closing peer-count question was never spent — absent, not
        // a figure read off a node already gone.
        #expect(report.connections == nil)
        #expect(networkCalls.withLock { $0 } == 0)
    }
    /// `step` reads a node still on its way down like a running one — it
    /// cannot be started, so the read is where its `noAnswer` is earned —
    /// but the read's own boundary honors the watch's rule: a stopped
    /// node is never asked. `getblockchaininfo` is spent nowhere on
    /// either budget shape; asking and then discarding would cost up to
    /// `questionBound` against a node that stops answering first.
    @Test(
        "a node already stopping is never asked — noAnswer costs no question",
        .timeLimit(.minutes(1)),
        arguments: [Duration.seconds(600), nil] as [Duration?])
    func stoppingNodeIsNeverAsked(syncBudget: Duration?) async throws {
        let test = ManualClock()
        let store = makeVolatileDefaults(
            distinguisher: syncBudget == nil ? "unbudgeted" : "budgeted")
        let calls = Mutex(0)
        let networkCalls = Mutex(0)
        let session = FakeRunSession(
            nodeState: .stopping,
            reader: StagedReader(
                blockchain: {
                    calls.withLock { $0 += 1 }
                    return try decodeWatchInfo()
                },
                network: {
                    networkCalls.withLock { $0 += 1 }
                    return try decodeNetworkInfo()
                }))
        let report = await NodeRun.perform(
            session: session, waitForFirstAnswer: .seconds(240),
            syncBudget: syncBudget,
            clock: test, now: { watchNow }, defaults: store)

        #expect(report.outcome == .noAnswer)
        #expect(report.syncEnding == .notMeasured)
        #expect(report.syncResult == .notMeasured)
        #expect(report.blockHeight == nil)
        #expect(report.blocksGainedThisRun == nil)
        #expect(report.connections == nil)
        // The refusal, not the report, is what this test weighs: a
        // question asked and then discarded would show exactly one call.
        #expect(calls.withLock { $0 } == 0)
        #expect(networkCalls.withLock { $0 } == 0)
    }
    /// A deliberate stop outranks a drifted condition standing on the
    /// same pass — the precedence `watchEnding` owns, exercised where it
    /// lives: critical heat lands while the first poll's answer is
    /// parked and the node is stopped beside it, so the pass reaches its
    /// gather holding both facts and ends `nodeStopped`, never
    /// `conditionsChanged` (spec scenario 18).
    @Test("a same-pass stop outranks a drifted condition — nodeStopped, not conditionsChanged", .timeLimit(.minutes(1)))
    func stoppedMidWatchBeatsDrift() async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults()
        let device = FakeDeviceReadings()
        let pollIssued = Gate()
        let releaseAnswer = Gate()
        let calls = Mutex(0)
        let session = FakeRunSession(
            nodeState: .running,
            reader: StagedReader(
                blockchain: {
                    let n = calls.withLock { n in n += 1; return n }
                    if n == 1 { return try decodeWatchInfo() }
                    // The watch's first question parks until both facts
                    // have landed — the pass gathers drift at decision
                    // time beside the stop.
                    pollIssued.open()
                    try await releaseAnswer.wait()
                    return try decodeWatchInfo()
                },
                network: { try decodeNetworkInfo() }),
            device: device)
        let done = Gate()
        let run = Task { @MainActor in
            // `pollIssued` is awaited directly below. Abandoned if the
            // run ends first, so the await fails by name instead of
            // wedging to `.timeLimit`.
            defer { pollIssued.abandon(); done.open() }
            return await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                syncBudget: .seconds(600),
                clock: clock.clock, now: { watchNow }, defaults: store)
        }
        defer { run.cancel() }
        // No drive: the first pass asks without any clock advance — the
        // gate, not a hop, proves the answer is parked mid-flight.
        try await pollIssued.wait()
        // The stop and the drift land together inside the parked answer.
        session.nodeState = .stopping
        device.scriptedThermalState = .critical
        releaseAnswer.open()
        try await done.wait()
        let report = await run.value

        #expect(report.syncEnding == .nodeStopped)
        #expect(report.syncResult == .nodeStopped)
        #expect(report.outcome == .alreadyRunning)
        // The drift gather still ran on the stopped pass — `networkCurrent`
        // is its read alone — so the ending is a ranked win, not a
        // skipped gather.
        let deviceCalls = device.calls.withLock { $0 }
        #expect(deviceCalls.filter { $0 == "networkCurrent" }.count == 1)
    }
    /// The stop ends the watch on the last good reading — not the entry
    /// figure, and never the answer that landed after the stop. Pass one
    /// banks a real gain; the node stops inside pass two's in-flight
    /// question; the measured report carries the earned height and the
    /// earned gain (FR-008's "earned outcome, last good reading").
    @Test("a stop mid-watch reports the last good reading — banked gain, late answer discarded", .timeLimit(.minutes(1)))
    func stoppedMidWatchKeepsEarnedGain() async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults()
        let secondPoll = Gate()
        let releaseAnswer = Gate()
        let calls = Mutex(0)
        let networkCalls = Mutex(0)
        let session = FakeRunSession(
            nodeState: .running,
            reader: StagedReader(
                blockchain: {
                    let n = calls.withLock { n in n += 1; return n }
                    switch n {
                    case 1: return try decodeWatchInfo()
                    // Pass one: a real +10 the watch banks.
                    case 2: return try decodeWatchInfo(blocks: 110, headers: 200)
                    // Pass two: parked until the stop has landed — its
                    // 150 is real but describes a node already gone.
                    default:
                        secondPoll.open()
                        try await releaseAnswer.wait()
                        return try decodeWatchInfo(blocks: 150, headers: 200)
                    }
                },
                network: {
                    networkCalls.withLock { $0 += 1 }
                    return try decodeNetworkInfo()
                }))
        let done = Gate()
        let run = ClockSubject.$isCurrent.withValue(true) {
            Task { @MainActor in
                // `secondPoll` must end on every verdict, not only the
                // parked one: the drive below targets it. Abandoned if the
                // run ends first, so the drive throws by name instead of
                // wedging to `.timeLimit`.
                defer { secondPoll.abandon(); done.open() }
                return await NodeRun.perform(
                    session: session, waitForFirstAnswer: .seconds(240),
                    syncBudget: .seconds(600),
                    clock: clock.clock, now: { watchNow }, defaults: store)
            }
        }
        defer { run.cancel() }
        // The first pass's bound holds until its answer lands; the nap
        // to the second is then the only armed deadline, so the drive
        // lands exactly on the parked second poll — its own bound held,
        // never advanced.
        try await clock.test.drive(untilDone: secondPoll)
        session.nodeState = .stopping
        releaseAnswer.open()
        try await done.wait()
        let report = await run.value

        #expect(report.syncEnding == .nodeStopped)
        #expect(report.syncResult == .nodeStopped)
        #expect(report.outcome == .alreadyRunning)
        // Pass one's 110 is what the report stands behind — not the
        // entry's 100, not the discarded 150.
        #expect(report.blockHeight == 110)
        #expect(report.blocksGainedThisRun == 10)
        // A stopped node is never asked — the closing peer count was
        // spent nowhere.
        #expect(report.connections == nil)
        #expect(networkCalls.withLock { $0 } == 0)
        // Three chain questions: the entry, the banked pass, the parked.
        #expect(calls.withLock { $0 } == 3)
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
            defer { pollIssued.abandon(); done.open() }
            return await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                syncBudget: .seconds(600),
                clock: clock.clock, now: { watchNow }, defaults: store)
        }
        defer { run.cancel() }
        // No drive: the first pass asks without any clock advance — the
        // gate, not a hop, proves the question is parked mid-flight.
        // This is the shape a starved runner once turned into a bound
        // firing under an in-flight answer: with nothing owed the clock,
        // delivery can only ever win.
        try await pollIssued.wait()
        run.cancel()
        releaseAnswer.open()
        try await done.wait()
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
        let run = ClockSubject.$isCurrent.withValue(true) {
            Task { @MainActor in
                defer { done.open() }
                return await NodeRun.perform(
                    session: session, waitForFirstAnswer: .seconds(240),
                    // Exactly the unproductive leash: the pass at t=120 holds
                    // both the tripped leash and the spent budget.
                    syncBudget: .seconds(120),
                    clock: clock.clock, now: { watchNow }, defaults: store)
            }
        }
        try await clock.test.drive(untilDone: done)
        let report = await run.value

        guard case .noProgress = report.syncEnding else {
            Issue.record("expected noProgress, got \(report.syncEnding)")
            return
        }
        #expect(report.blocksGainedThisRun == 0)
    }
    /// The device drift a pass can refuse on — one case per verdict the
    /// narrow gather weighs; the weigh-in's wider refusals are not
    /// re-polled mid-watch — a spec-deferred check, not an impossible one.
    enum MidWatchDrift {
        case metered, dataRestricted, criticalHeat, lowPowerMode

        /// The refusal `driftedCondition` names for this flip.
        var refusal: NodePreflight.Refusal {
            switch self {
            case .metered: .meteredNetwork
            case .dataRestricted: .dataRestrictedNetwork
            case .criticalHeat: .overheating
            case .lowPowerMode: .lowPowerMode
            }
        }

        /// The one reading each case turns mid-watch. `@MainActor` like
        /// the fake it scripts — a nested type does not inherit the
        /// suite's isolation.
        @MainActor
        func inject(on device: FakeDeviceReadings) {
            switch self {
            case .metered:
                device.scriptedNetworkCurrent = NetworkCost(
                    isMetered: true, isDataRestricted: false)
            case .dataRestricted:
                device.scriptedNetworkCurrent = NetworkCost(
                    isMetered: false, isDataRestricted: true)
            case .criticalHeat:
                device.scriptedThermalState = .critical
            case .lowPowerMode:
                device.isLowPowerModeEnabled = true
            }
        }
    }
    /// Every pass weighs the narrow drift gather: a condition flipped on
    /// while the answer is in flight ends the run `conditionsChanged` on
    /// the pass that saw it — never one late — naming what turned
    /// (FR-010, FR-011). `networkCurrent`'s one read pins the gather to
    /// exactly that pass, and `networkFirst`'s one — the weigh-in's —
    /// proves the drift check never waits on the network.
    @Test(
        "a condition landing mid-watch ends conditionsChanged naming it",
        .timeLimit(.minutes(1)),
        arguments: [
            MidWatchDrift.metered, .dataRestricted,
            .criticalHeat, .lowPowerMode])
    func midWatchDriftEndsConditionsChanged(drift: MidWatchDrift) async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults(distinguisher: String(describing: drift))
        let device = FakeDeviceReadings()
        let pollIssued = Gate()
        let releaseAnswer = Gate()
        let calls = Mutex(0)
        var emitted: [NodeRun.ProgressUpdate] = []
        let session = FakeRunSession(
            nodeState: .running,
            reader: StagedReader(
                blockchain: {
                    let n = calls.withLock { n in n += 1; return n }
                    if n == 1 { return try decodeWatchInfo() }
                    // The watch's first question parks until the flipped
                    // condition has landed — the pass then gathers drift
                    // at decision time, not at ask time.
                    pollIssued.open()
                    try await releaseAnswer.wait()
                    return try decodeWatchInfo()
                },
                network: { try decodeNetworkInfo() }),
            device: device)
        let done = Gate()
        let run = Task { @MainActor in
            defer { pollIssued.abandon(); done.open() }
            return await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                syncBudget: .seconds(600),
                clock: clock.clock, now: { watchNow }, defaults: store) {
                emitted.append($0)
            }
        }
        defer { run.cancel() }
        // No drive: the first pass asks without any clock advance — the
        // gate, not a hop, proves the answer is parked mid-flight.
        try await pollIssued.wait()
        // The condition lands while the first poll's answer is in flight.
        drift.inject(on: device)
        releaseAnswer.open()
        // The released answer, the drift gather, and the
        // `conditionsChanged` ending all resolve on the spot.
        try await done.wait()
        let report = await run.value

        #expect(report.syncEnding == .conditionsChanged(drift.refusal))
        #expect(report.syncResult == .conditionsChanged)
        // The node is left running and the card showed a headline —
        // the watch committed before the drifted pass.
        #expect(report.outcome == .alreadyRunning)
        #expect(emitted.contains { $0.headline != nil })
        // The band-separation invariant holds on every drift variant:
        // a flat watch is where sortedness alone goes blind — every
        // pass rewrites the same position — so the pin is that each
        // write either self-identifies as a watch write or stays
        // strictly inside the start-up band; the closing claim is the
        // only emission that could violate it.
        #expect(emitted.allSatisfy {
            $0.headline != nil || $0.fraction < NodeAutomation.startUpBandEnd
        })
        // A flat answer against the entry reading earned nothing.
        #expect(report.blocksGainedThisRun == 0)
        let deviceCalls = device.calls.withLock { $0 }
        // One pass lived — the gather's `networkCurrent` read happened
        // exactly once — and `networkFirst` is the weigh-in's alone.
        #expect(deviceCalls.filter { $0 == "networkCurrent" }.count == 1)
        #expect(deviceCalls.filter { $0 == "networkFirst" }.count == 1)
    }
    /// The two states the drift check deliberately tolerates, scripted
    /// together on the only path that can produce them: thermal
    /// `.serious` lands mid-watch and changes nothing — `.critical` is
    /// the bar — and Low Power Mode on *when the watch commits* is a
    /// standing preference, not a delta (FR-011). Only the start path
    /// reaches that shape: preflight reads the mode before the flip, and
    /// every other consent refuses it outright, so it only ever arrives
    /// switched on between consent and commit — here, while the first
    /// answer waits. The watch runs its whole budget on both and ends on
    /// time, not on a condition.
    @Test(
        "tolerated states never end the watch — serious heat, Low Power at entry",
        .timeLimit(.minutes(1)))
    func toleratedStatesNeverEndWatch() async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults()
        let device = FakeDeviceReadings()
        let firstAnswerIssued = Gate()
        let releaseEntry = Gate()
        let committed = Gate()
        let calls = Mutex(0)
        var emitted: [NodeRun.ProgressUpdate] = []
        let session = FakeRunSession(
            nodeState: .stopped,
            reader: StagedReader(
                blockchain: {
                    let n = calls.withLock { n in n += 1; return n }
                    if n == 1 {
                        // The first-answer wait's question parks until
                        // both tolerated states are in place: they must
                        // land after preflight's gather — which refuses
                        // either — and before the commit's Low-Power
                        // snapshot.
                        firstAnswerIssued.open()
                        try await releaseEntry.wait()
                    }
                    return try decodeWatchInfo()
                },
                network: { try decodeNetworkInfo() }),
            device: device)
        session.startNodeResult = true
        let done = Gate()
        let run = ClockSubject.$isCurrent.withValue(true) {
            Task { @MainActor in
                // `firstAnswerIssued`/`committed` are awaited below.
                // Abandoned if the run ends first, so the awaits fail by
                // name instead of wedging.
                defer {
                    firstAnswerIssued.abandon(); committed.abandon(); done.open()
                }
                return await NodeRun.perform(
                    session: session, waitForFirstAnswer: .seconds(240),
                    syncBudget: .seconds(30),
                    clock: clock.clock, now: { watchNow }, defaults: store) {
                    emitted.append($0)
                    if $0.headline != nil { committed.open() }
                }
            }
        }
        defer { run.cancel() }
        // No drive to reach the parked question — the first-answer
        // wait's ask issues without any clock advance.
        try await firstAnswerIssued.wait()
        // `.serious` lands after preflight read `.nominal`; Low Power
        // lands between the gather's off reading and the commit's
        // snapshot — `lowPowerModeAtEntry` is then true, so the per-pass
        // reads see no delta, and `.serious` stays under the mid-watch bar.
        device.scriptedThermalState = .serious
        device.isLowPowerModeEnabled = true
        releaseEntry.open()
        // The commit's headline proves the released answer landed and
        // the weigh-in passed.
        try await committed.wait()
        try await clock.test.drive(untilDone: done)
        let report = await run.value

        #expect(report.syncEnding == .stillSyncing)
        #expect(report.syncResult == .stillSyncing)
        // The start path's own outcome — the node is left running.
        #expect(report.outcome == .started)
        #expect(emitted.contains { $0.headline != nil })
        // The watch ran flat — every pass rewrote the same band
        // position — so this is also where sortedness must hold over
        // the *full* sequence (a terminal ceiling write sorts cleanly
        // here) and the invariant does the catching: each write is a
        // self-identified watch write or strictly inside the band.
        let emittedFractions = emitted.map(\.fraction)
        #expect(emittedFractions == emittedFractions.sorted())
        #expect(emitted.allSatisfy {
            $0.headline != nil || $0.fraction < NodeAutomation.startUpBandEnd
        })
        let deviceCalls = device.calls.withLock { $0 }
        // `networkCurrent` is the drift gather's alone — nothing else
        // reads it — so its count is the pass count, and a pass is the
        // headline write: one lands every pass, ending or not, beside
        // the commit's one. Gathers == headline writes − commit == passes.
        #expect(
            deviceCalls.filter { $0 == "networkCurrent" }.count
                == emitted.filter { $0.headline != nil }.count - 1)
        // `networkFirst` is the preflight gather's one — the watch never
        // waited on the network across every pass it lived.
        #expect(deviceCalls.filter { $0 == "networkFirst" }.count == 1)
    }

}

#endif
