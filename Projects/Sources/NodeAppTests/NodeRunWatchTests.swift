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
///
/// The suite is split by the watch's phases: the cross-cutting canaries
/// live here; `+Entry` covers the weigh-in gate and the run baseline,
/// `+Lifecycle` the mid-watch stops, cancels, drift, and leash, and
/// `+PeerEvidence` the `getpeerinfo` ride-along.
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
        // The mark is what lets the drive tell the run's own naps (the
        // subject's, inherited by `Task { }` children) from the bounds
        // its questions park (`Task.detached`, never inherited).
        let run = ClockSubject.$isCurrent.withValue(true) {
            Task { @MainActor in
                defer { done.open() }
                return await NodeRun.perform(
                    session: session, waitForFirstAnswer: .seconds(240),
                    syncBudget: .seconds(600),
                    clock: clock.clock, now: { watchNow }, defaults: store) {
                    emitted.append($0)
                }
            }
        }
        // A parked bound holds the clock until its answer cancels it —
        // the drive can never reach a deadline ahead of the work.
        try await clock.test.drive(untilDone: done)
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
        // The *full* sequence is sorted, not just the watch writes —
        // filtering first is what let the measured report's closing
        // "bar full" claim land unchallenged: banded to the start-up
        // ceiling, it would read here as a 0.95 → 0.1 retreat the
        // meter's floor hides but the sequence must not contain.
        let emittedFractions = emitted.map(\.fraction)
        #expect(emittedFractions == emittedFractions.sorted())
        // The band-separation invariant: every write either
        // self-identifies as a watch write or stays strictly inside the
        // start-up band — the suppressed closing claim is the one
        // emission that could break it (headline-less, at the ceiling).
        #expect(emitted.allSatisfy {
            $0.headline != nil || $0.fraction < NodeAutomation.startUpBandEnd
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
        let run = ClockSubject.$isCurrent.withValue(true) {
            Task { @MainActor in
                defer { done.open() }
                return await NodeRun.perform(
                    session: session, waitForFirstAnswer: .seconds(240),
                    syncBudget: .seconds(60),
                    clock: clock.clock, now: { watchNow }, defaults: store)
            }
        }
        try await clock.test.drive(untilDone: done)
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
    /// The starvation the drive exists to prevent: an answer that costs
    /// real executor time — fifty wall-clock milliseconds per question —
    /// must land inside its bound on every pass. A bound holds the clock
    /// until the answer cancels it, so the drive can never reach a
    /// deadline first whatever the runner's load — the guarantee the
    /// stepped drive could only ever buy probabilistically: its ~1 ms
    /// per hop crossed this question's 30 s bound in ~6 ms, dropping
    /// every answer and re-asking the whole budget away.
    @Test("an answer costing real executor time still lands inside every bound", .timeLimit(.minutes(1)))
    func realLatencyAnswersInsideBound() async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults()
        let calls = Mutex(0)
        let session = FakeRunSession(
            nodeState: .starting,
            reader: StagedReader(
                blockchain: {
                    let n = calls.withLock { n in n += 1; return n }
                    // The answer costs real time on the real clock —
                    // nothing the injected one can shorten.
                    try await Task.sleep(for: .milliseconds(50))
                    switch n {
                    case 1: return try decodeWatchInfo(blocks: 100, headers: 200)
                    case 2: return try decodeWatchInfo(blocks: 110, headers: 200)
                    case 3: return try decodeWatchInfo(blocks: 140, headers: 200)
                    default: return try decodeWatchInfo(
                        blocks: 210, headers: 210, ibd: false)
                    }
                },
                network: { try decodeNetworkInfo() }))
        var emitted: [NodeRun.ProgressUpdate] = []
        let done = Gate()
        let run = ClockSubject.$isCurrent.withValue(true) {
            Task { @MainActor in
                defer { done.open() }
                return await NodeRun.perform(
                    session: session, waitForFirstAnswer: .seconds(240),
                    syncBudget: .seconds(600),
                    clock: clock.clock, now: { watchNow }, defaults: store) {
                    emitted.append($0)
                }
            }
        }
        try await clock.test.drive(untilDone: done)
        let report = await run.value

        #expect(report.syncEnding == .caughtUp)
        #expect(report.outcome == .alreadyRunning)
        #expect(report.blocksGainedThisRun == 110)
        // Every slow answer landed — the entry, two advancing passes,
        // the catch-up — each asked exactly once: a starved bound would
        // have spent a re-ask on the next scripted figure and shifted
        // the whole count.
        #expect(calls.withLock { $0 } == 4)
        #expect(emitted.filter { $0.headline != nil }.count == 4)
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

}

#endif
