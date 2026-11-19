//
//  NodeRunWatchTests+PeerEvidence.swift
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

/// The `getpeerinfo` ride-along — which pass shape spends it,
/// how often, and what its answers weigh toward `caughtUp`.
extension NodeRunWatchTests {

    /// The ride-along's one question: a pass that fed the `.flatWindow`
    /// leash and cannot otherwise prove a catch-up asks `getpeerinfo`
    /// once — and two confirming block-serving peers end the watch
    /// `caughtUp` on the pass that asked (FR-006). The literal-
    /// qualifying *gain* a pass earlier — blocks catching the headers,
    /// flag clear, gap closed, headers unmoved — never asks: the leash
    /// the pass fed is the qualifier, not the reading's shape alone.
    @Test("a qualifying flat pass asks peers once — confirming peers end caughtUp", .timeLimit(.minutes(1)))
    func qualifyingFlatPassAsksPeersOnce() async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults()
        let calls = Mutex(0)
        let peerCalls = Mutex(0)
        let writes = Mutex(0)
        let writesAtAsk = Mutex(0)
        var emitted: [NodeRun.ProgressUpdate] = []
        let session = FakeRunSession(
            nodeState: .starting,
            reader: StagedReader(
                blockchain: {
                    let n = calls.withLock { n in n += 1; return n }
                    // The first-answer wait's read (entry): a gap the
                    // gate admits. Every watch answer is then the closed,
                    // flag-clear, stale-tipped figure — pass 1 a gain,
                    // every later pass qualifying flat, and on a tip this
                    // stale only the peer leg can ever fire.
                    return try decodeWatchInfo(
                        blocks: n == 1 ? 200 : 210, headers: 210,
                        ibd: false)
                },
                peers: {
                    peerCalls.withLock { $0 += 1 }
                    // What the ask saw already written: the pass's
                    // liveness write lands *before* the ride-along, so a
                    // question parked at its bound never delays it.
                    writesAtAsk.withLock { $0 = writes.withLock { $0 } }
                    return [
                        try decodePeer(
                            connectionType: "outbound-full-relay",
                            inbound: false, syncedHeaders: 210),
                        try decodePeer(
                            connectionType: "block-relay-only",
                            inbound: false, syncedHeaders: 210),
                    ]
                },
                network: { try decodeNetworkInfo() }))
        let done = Gate()
        let run = ClockSubject.$isCurrent.withValue(true) {
            Task { @MainActor in
                defer { done.open() }
                return await NodeRun.perform(
                    session: session, waitForFirstAnswer: .seconds(240),
                    syncBudget: .seconds(600),
                    clock: clock.clock, now: { watchNow }, defaults: store) {
                    writes.withLock { $0 += 1 }
                    emitted.append($0)
                }
            }
        }
        try await clock.test.drive(untilDone: done)
        let report = await run.value

        #expect(report.syncEnding == .caughtUp)
        #expect(report.outcome == .alreadyRunning)
        // Exactly one ask, on the one qualifying flat pass — the gain
        // pass before it spent none, and the run ended caughtUp on the
        // pass that asked.
        #expect(peerCalls.withLock { $0 } == 1)
        #expect(report.blocksGainedThisRun == 10)
        // The moved liveness write still lands once per pass: the
        // commit's plus one each on the gain and the qualifying flat.
        let watchWrites = emitted.filter { $0.headline != nil }.count
        #expect(watchWrites == 3)
        // And it lands *ahead* of the ask: the question observed all
        // four writes so far — a write left at pass's end would show
        // one fewer on the ask that saw it.
        #expect(writesAtAsk.withLock { $0 } == 4)
    }
    /// A flat pass whose tip reads fresh never spends the peer ask —
    /// the non-peer legs of `caughtUp` are tried before the ride-along
    /// is spent, so the pass ends on the proof it already had. This is
    /// the one shape where a flat pass could otherwise pay a question
    /// bound for evidence it does not need.
    @Test("a fresh-tipped flat pass ends caughtUp without asking peers", .timeLimit(.minutes(1)))
    func freshTippedFlatPassNeverAsksPeers() async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults()
        let calls = Mutex(0)
        let peerCalls = Mutex(0)
        let session = FakeRunSession(
            nodeState: .starting,
            reader: StagedReader(
                blockchain: {
                    let n = calls.withLock { n in n += 1; return n }
                    // Entry: a gap the gate admits. The first pass is a
                    // gain — blocks closing on the headers, tip still
                    // stale so nothing ends. The second is the same
                    // closed figure flat, but the tip now reads fresh:
                    // the freshness leg proves the catch-up before the
                    // ride-along is asked.
                    return try decodeWatchInfo(
                        blocks: n == 1 ? 200 : 210, headers: 210,
                        ibd: false,
                        tip: n <= 2
                            ? watchNow.timeIntervalSince1970 - 7_200
                            : watchNow.timeIntervalSince1970)
                },
                peers: {
                    peerCalls.withLock { $0 += 1 }
                    return []
                },
                network: { try decodeNetworkInfo() }))
        let done = Gate()
        let run = ClockSubject.$isCurrent.withValue(true) {
            Task { @MainActor in
                defer { done.open() }
                return await NodeRun.perform(
                    session: session, waitForFirstAnswer: .seconds(240),
                    syncBudget: .seconds(600),
                    clock: clock.clock, now: { watchNow }, defaults: store) {
                    _ = $0
                }
            }
        }
        try await clock.test.drive(untilDone: done)
        let report = await run.value

        #expect(report.syncEnding == .caughtUp)
        #expect(report.outcome == .alreadyRunning)
        // The qualifying flat pass ended on the freshness leg — the
        // peer question was spent nowhere.
        #expect(peerCalls.withLock { $0 } == 0)
    }
    /// An unhelpful peer answer — a failed ask and an empty one alike —
    /// is simply no evidence: each qualifying flat pass spends its one
    /// question, none ends `caughtUp`, and the watch runs the budget out
    /// on its own verdicts rather than inventing a proof.
    @Test(
        "an unhelpful peer answer keeps watching — evidence is never invented",
        .timeLimit(.minutes(1)), arguments: [true, false])
    func unhelpfulPeerAnswerKeepsWatching(throwing: Bool) async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults(
            distinguisher: throwing ? "throwing" : "empty")
        let calls = Mutex(0)
        let peerCalls = Mutex(0)
        let session = FakeRunSession(
            nodeState: .starting,
            reader: StagedReader(
                blockchain: {
                    let n = calls.withLock { n in n += 1; return n }
                    return try decodeWatchInfo(
                        blocks: n == 1 ? 200 : 210, headers: 210,
                        ibd: false)
                },
                peers: {
                    peerCalls.withLock { $0 += 1 }
                    if throwing { throw StagedReader.NotScripted() }
                    return []
                },
                network: { try decodeNetworkInfo() }))
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

        #expect(report.syncEnding == .stillSyncing)
        // Every qualifying flat pass asked exactly once — the unhelpful
        // answers were weighed as no evidence: the entry ask and the
        // gain pass spent nothing, every flat pass spent one.
        #expect(peerCalls.withLock { $0 } == calls.withLock { $0 } - 2)
    }
    /// A run whose passes advance never spends the ride-along — the
    /// catch-up proved itself on the `headersAdvanced` leg, so the peer
    /// question was owed nowhere: `.flatWindow` is the only pass shape
    /// that asks.
    @Test("an advancing run never asks peers", .timeLimit(.minutes(1)))
    func advancingRunNeverAsksPeers() async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults()
        let calls = Mutex(0)
        let peerCalls = Mutex(0)
        let session = FakeRunSession(
            nodeState: .starting,
            reader: StagedReader(
                blockchain: {
                    let n = calls.withLock { n in n += 1; return n }
                    switch n {
                    case 1: return try decodeWatchInfo(blocks: 100, headers: 200)
                    case 2: return try decodeWatchInfo(blocks: 110, headers: 200)
                    case 3: return try decodeWatchInfo(blocks: 140, headers: 200)
                    // Flag clears, headers land past the entry figure —
                    // the `headersAdvanced` leg, peers never needed.
                    default: return try decodeWatchInfo(
                        blocks: 210, headers: 210, ibd: false)
                    }
                },
                peers: {
                    peerCalls.withLock { $0 += 1 }
                    return []
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
        #expect(peerCalls.withLock { $0 } == 0)
    }
    /// A stop landing while the ride-along question is parked still ends
    /// the pass `nodeStopped` — the deliberate action outranks whatever
    /// the answer would have proven, and a stopped node is never asked
    /// for peer evidence again.
    @Test("a node stopped inside the peer ask ends nodeStopped, no further ask", .timeLimit(.minutes(1)))
    func stoppedInsidePeerAskEndsNodeStopped() async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults()
        let peerAsked = Gate()
        let releasePeers = Gate()
        let peerCalls = Mutex(0)
        let session = FakeRunSession(
            nodeState: .running,
            reader: StagedReader(
                // The closed, flag-clear, stale-tipped figure — admitted
                // on the staleness leg alone — so the watch's first pass
                // is already qualifying flat and its ride-along fires
                // immediately.
                blockchain: {
                    try decodeWatchInfo(blocks: 210, headers: 210, ibd: false)
                },
                peers: {
                    peerCalls.withLock { $0 += 1 }
                    // The question parks mid-flight until the stop has
                    // landed — the pass can only reach its post-ask
                    // re-read already stopped.
                    peerAsked.open()
                    try await releasePeers.wait()
                    return []
                },
                network: { try decodeNetworkInfo() }))
        let done = Gate()
        let run = Task { @MainActor in
            defer { peerAsked.abandon(); done.open() }
            return await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                syncBudget: .seconds(600),
                clock: clock.clock, now: { watchNow }, defaults: store)
        }
        defer { run.cancel() }
        // No drive: the qualifying pass asks without any clock advance —
        // the gate, not a hop, proves the peer question is parked.
        try await peerAsked.wait()
        session.nodeState = .stopping
        releasePeers.open()
        try await done.wait()
        let report = await run.value

        #expect(report.syncEnding == .nodeStopped)
        // The parked ask was the only one — a stopped node is never
        // queried for peer evidence.
        #expect(peerCalls.withLock { $0 } == 1)
    }
    /// A peer ask that never answers is spent only up to its own bound —
    /// `min(questionBound, remaining)`, so the run's deadline stays hard:
    /// the parked question times out as no evidence, the pass falls
    /// through to the leashes, and the run still ends `stillSyncing` at
    /// its budget rather than one bound late. A bound that ignored the
    /// remaining budget would let the parked question outlive the
    /// deadline the run is accountable to.
    @Test("a peer ask that runs out its clock is no evidence, spent once and bounded", .timeLimit(.minutes(1)))
    func timedOutPeerAnswerIsNoEvidence() async throws {
        let clock = watchClock()
        let store = makeVolatileDefaults()
        let calls = Mutex(0)
        let peerCalls = Mutex(0)
        let peerAsked = Gate()
        let session = FakeRunSession(
            nodeState: .starting,
            reader: StagedReader(
                blockchain: {
                    let n = calls.withLock { n in n += 1; return n }
                    // Entry: a gap the gate admits. Blocks keep gaining
                    // until the sixth read, so the first qualifying flat
                    // pass lands ~30 s in — ~15 s of budget left, inside
                    // one question bound: the ask's bound is then what
                    // decides whether the deadline holds.
                    return try decodeWatchInfo(
                        blocks: n == 1 ? 200 : min(200 + (n - 1) * 2, 210),
                        headers: 210, ibd: false)
                },
                peers: {
                    peerCalls.withLock { $0 += 1 }
                    peerAsked.open()
                    // The question that never answers: cancellation
                    // cannot reach it, so only its own bound releases
                    // the pass — `waitIgnoringCancellation`, not a gate
                    // the test opens.
                    await Gate().waitIgnoringCancellation()
                    return []
                },
                network: { try decodeNetworkInfo() }))
        let done = Gate()
        let run = ClockSubject.$isCurrent.withValue(true) {
            Task { @MainActor in
                // `peerAsked` is driven toward below. Abandoned if the
                // run ends first, so the drive throws by name instead of
                // wedging to `.timeLimit`.
                defer { peerAsked.abandon(); done.open() }
                return await NodeRun.perform(
                    session: session, waitForFirstAnswer: .seconds(240),
                    syncBudget: .seconds(45),
                    clock: clock.clock, now: { watchNow }, defaults: store) {
                    _ = $0
                }
            }
        }
        // Gate first: the ride-along's question is provably in flight —
        // its bound the only sleeper the drive still holds.
        try await clock.test.drive(untilDone: peerAsked)
        // Then the test, not the drive, decides the bound must win:
        // expire it explicitly — the bound is `min(questionBound,
        // remaining)`, so the deadline it fires at is the run's own. A
        // run that already ended skips it — nothing will ever park —
        // and the assertions below fail on the verdict it earned.
        if !done.isOpen {
            try await clock.test.expireEarliestBound()
        }
        try await clock.test.drive(untilDone: done)
        let report = await run.value

        #expect(report.syncEnding == .stillSyncing)
        // The parked ask was spent exactly once — the bound, not a
        // re-ask, is what released the pass.
        #expect(peerCalls.withLock { $0 } == 1)
        #expect(calls.withLock { $0 } == 7)
        // And it fired on the run's own deadline: the bound armed at
        // t=25 owed `min(30, 45-25)` — the 45 s budget, to the instant.
        #expect(clock.test.now.offset == .seconds(45))
    }

}

#endif
