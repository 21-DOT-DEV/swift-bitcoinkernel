//
//  NodeRunTests.swift
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

/// Two baselines live beside each other: the observational `last_known_*` (the
/// sync poll writes it every 30 s while the node runs; the dashboard reads it)
/// and the run-owned `last_run_*` — the "blocks since last check" baseline,
/// which only a report actually returned as a result may move. These tests pin
/// the contract the actions rely on: a returned result updates the run
/// baseline always and the observational one unless it would rewind a fresher
/// same-chain reading, anything less updates neither, and the poll's writes
/// never touch the run baseline.
@Suite("Last-known tip persistence")
struct NodeRunTests {

    @MainActor
    @Test("a report carrying a measurement updates both baselines")
    func measuredReportPersists() {
        let defaults = makeVolatileDefaults()
        NodeViewModel.persistLastRun(height: 100, chain: "main", in: defaults)
        NodeViewModel.persistLastKnown(height: 100, chain: "main", in: defaults)
        let report = NodeRunReport(
            outcome: .started, syncEnding: .notMeasured,
            chain: "main", blockHeight: 110, blocksGainedThisRun: nil,
            dialogTemplate: "Node running.")
        NodeRun.persistReportedTip(from: report, to: defaults)
        // A returned result is both the run baseline and a real observation.
        #expect(NodeViewModel.lastRun(in: defaults)?.height == 110)
        #expect(NodeViewModel.lastKnown(in: defaults)?.height == 110)
        #expect(NodeViewModel.lastRun(in: defaults)?.chain == "main")
    }

    @MainActor
    @Test("a run that measured nothing leaves both baselines alone")
    func unmeasuredReportDoesNotPersist() {
        // The paths the actions gate on all produce reports with no height —
        // cancelled, node-stopped, declined, timed out. Whatever the report
        // claims happened, absent fields mean nothing to write.
        let defaults = makeVolatileDefaults()
        NodeViewModel.persistLastRun(height: 100, chain: "main", in: defaults)
        NodeViewModel.persistLastKnown(height: 100, chain: "main", in: defaults)
        NodeRun.persistReportedTip(from: NodeRun.noAnswerReport(), to: defaults)
        NodeRun.persistReportedTip(
            from: NodeRunReport(
                outcome: .declined, syncEnding: .notMeasured,
                chain: nil, blockHeight: nil, blocksGainedThisRun: nil,
                dialogTemplate: "The node did not start."),
            to: defaults)
        #expect(NodeViewModel.lastRun(in: defaults)?.height == 100)
        #expect(NodeViewModel.lastKnown(in: defaults)?.height == 100)
    }

    @MainActor
    @Test("a half-measured report does not persist — the baseline needs the pair")
    func halfMeasuredReportDoesNotPersist() {
        // Height without its chain is not a baseline: a tip means nothing
        // unless it says which chain it sits on, so the guard requires both.
        let defaults = makeVolatileDefaults()
        NodeViewModel.persistLastRun(height: 100, chain: "main", in: defaults)
        NodeRun.persistReportedTip(
            from: NodeRunReport(
                outcome: .started, syncEnding: .notMeasured,
                chain: nil, blockHeight: 110, blocksGainedThisRun: nil,
                dialogTemplate: "Node running."),
            to: defaults)
        #expect(NodeViewModel.lastRun(in: defaults)?.height == 100)
        #expect(NodeViewModel.lastKnown(in: defaults) == nil)
    }

    @MainActor
    @Test("the poll's observational writes never move the run's baseline")
    func pollDoesNotAdvanceRunBaseline() {
        // The guarantee the key split exists for: `refreshSyncState` writes
        // `last_known_*` every 30 seconds while a node runs. If it also moved
        // `last_run_*`, "blocks since last check" would collapse toward zero
        // whenever the app had been alive recently.
        let defaults = makeVolatileDefaults()
        NodeViewModel.persistLastRun(height: 100, chain: "main", in: defaults)
        // What the poll does, twice over.
        NodeViewModel.persistLastKnown(height: 140, chain: "main", in: defaults)
        NodeViewModel.persistLastKnown(height: 150, chain: "main", in: defaults)
        #expect(NodeViewModel.lastKnown(in: defaults)?.height == 150)
        #expect(NodeViewModel.lastRun(in: defaults)?.height == 100)
    }

    @MainActor
    @Test("a returned tip older than the poll's latest does not rewind the dashboard")
    func staleTipDoesNotRewindObservational() {
        // The poll can write a newer height while the run asks its last
        // question — the report's reading is then seconds stale by the time
        // it is returned. `last_run_*` still records exactly what the run
        // reported; `last_known_*` keeps the fresher observation rather than
        // stepping the dashboard's "last validated" a block backward until
        // the next poll corrects it.
        let defaults = makeVolatileDefaults()
        NodeViewModel.persistLastKnown(height: 150, chain: "main", in: defaults)
        let report = NodeRunReport(
            outcome: .alreadyRunning, syncEnding: .notMeasured,
            chain: "main", blockHeight: 140, blocksGainedThisRun: nil,
            dialogTemplate: "Node already running.")
        NodeRun.persistReportedTip(from: report, to: defaults)
        #expect(NodeViewModel.lastKnown(in: defaults)?.height == 150)
        // The run-owned baseline records what was reported — unconditionally.
        #expect(NodeViewModel.lastRun(in: defaults)?.height == 140)
    }

    @MainActor
    @Test("a chain-switch report updates the observational store even at a lower height")
    func chainSwitchStillUpdatesObservational() {
        // The rewind guard compares tips on the *same* chain only: after a
        // main→signet switch, "last validated" must follow the node to the
        // new chain rather than stay stuck on a taller mainnet tip forever.
        let defaults = makeVolatileDefaults()
        NodeViewModel.persistLastKnown(height: 800_000, chain: "main", in: defaults)
        let report = NodeRunReport(
            outcome: .alreadyRunning, syncEnding: .notMeasured,
            chain: "signet", blockHeight: 5, blocksGainedThisRun: nil,
            dialogTemplate: "Node already running.")
        NodeRun.persistReportedTip(from: report, to: defaults)
        #expect(NodeViewModel.lastKnown(in: defaults)?.chain == "signet")
        #expect(NodeViewModel.lastKnown(in: defaults)?.height == 5)
        #expect(NodeViewModel.lastRun(in: defaults)?.chain == "signet")
    }
}

/// The seams T018 opens up: `NodeRun.perform` takes the session it asks, the
/// clock it measures on, and the store it reads baselines from — so a test can
/// drive the run itself, without a node, a Tor network, or the app's real
/// settings. These tests pin the persistence contract at the two places a run
/// can die after producing work: mid-question, where the last "still wanted?"
/// check discards the answer that lands too late, and the result boundary the
/// intents share, where a run cancelled or stopped in the final span must
/// throw rather than return — so nothing is persisted for a run that reported
/// nothing.
///
/// Every wait is event-driven (`Gate`) or clock-driven (an injected clock):
/// no test sleeps real time, so nothing here is timing-lucky. Where a test
/// must prove the run actually asked its injected clock, `ObservedClock`
/// records each sleep request — a `ManualClock` alone cannot see who was
/// asked.
@Suite("Run drivability")
@MainActor
struct NodeRunDrivabilityTests {

    /// A session found running — the path the run reads and leaves alone.
    /// The peer-count question is the run's last; parking or delaying it puts
    /// a real answer on the table and the run mid-question, which is the state
    /// a cancel or a node-stop lands in.
    private func sessionAnswering(
        network: @escaping @Sendable () async throws -> NetworkInfo
    ) -> FakeRunSession {
        FakeRunSession(
            nodeState: .running,
            reader: StagedReader(
                blockchain: { try decodeBlockchainInfo() }, network: network))
    }

    @Test("the run reports its progress as typed updates — fractions only, so far")
    func progressReportsArriveAsUpdates() async {
        // The emissions were unverifiable while the callback stayed a bare
        // `Double` nobody passed — every test below lets it default away.
        // Recorded on the report path, the run's shortest emission sequence:
        // first question out, last question out, work complete.
        var emitted: [NodeRun.ProgressUpdate] = []
        let session = sessionAnswering(network: { try decodeNetworkInfo() })
        _ = await NodeRun.perform(
            session: session, waitForFirstAnswer: .seconds(30),
            clock: ManualClock(), defaults: makeVolatileDefaults()
        ) { emitted.append($0) }
        #expect(emitted.map(\.fraction) == [0.1, 0.6, 1])
        // `headline`/`detail` ride the payload already — `nil` until the watch
        // stage produces them and T030 writes them to the card.
        #expect(emitted.allSatisfy { $0.headline == nil && $0.detail == nil })
    }

    @Test("a run cancelled mid-question reports nothing measured and persists nothing")
    func cancellationMidQuestionPersistsNothing() async throws {
        let store = makeVolatileDefaults()
        // Baselines already on record — distinctive values, below what the
        // run's own reading would write — so a persist sneaked back into the
        // run lands as a wrong value rather than hiding in a nil store.
        NodeViewModel.persistLastRun(height: 90, chain: "signet", in: store)
        NodeViewModel.persistLastKnown(height: 95, chain: "signet", in: store)
        #expect(NodeViewModel.lastRun(in: store)?.height == 90)
        #expect(NodeViewModel.lastKnown(in: store)?.height == 95)
        let questionEntered = Gate()
        let session = sessionAnswering(network: {
            questionEntered.open()
            // The RPC parks until the question bound cancels it — a call that
            // cannot return while the run is being torn down.
            try await Gate().wait()
            return try decodeNetworkInfo()
        })
        let run = Task { @MainActor in
            await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(30),
                clock: ManualClock(), defaults: store)
        }
        // Ordered on the event, not a guess at elapsed time: the cancel lands
        // only once the last question is provably in flight.
        try await questionEntered.wait()
        run.cancel()
        let report = await run.value
        // The in-flight answer never counted: the report carries no
        // measurement — and the seeded baselines come through untouched,
        // which is the "persists nothing" the name claims.
        #expect(report.outcome == .noAnswer)
        #expect(report.blockHeight == nil)
        #expect(NodeViewModel.lastRun(in: store)?.height == 90)
        #expect(NodeViewModel.lastRun(in: store)?.chain == "signet")
        #expect(NodeViewModel.lastKnown(in: store)?.height == 95)
        #expect(NodeViewModel.lastKnown(in: store)?.chain == "signet")
    }

    @Test("a node stopped mid-question discards the answer that lands after and persists nothing")
    func nodeStoppedMidQuestionPersistsNothing() async throws {
        let store = makeVolatileDefaults()
        // Baselines already on record — distinctive values, below what the
        // run's own reading would write — so a persist sneaked back into the
        // run lands as a wrong value rather than hiding in a nil store.
        NodeViewModel.persistLastRun(height: 90, chain: "signet", in: store)
        NodeViewModel.persistLastKnown(height: 95, chain: "signet", in: store)
        #expect(NodeViewModel.lastRun(in: store)?.height == 90)
        #expect(NodeViewModel.lastKnown(in: store)?.height == 95)
        let questionEntered = Gate()
        let answerReleased = Gate()
        let session = sessionAnswering(network: {
            questionEntered.open()
            // The RPC cannot be called back: it answers whenever the node gets
            // around to it — here, after the node has already been stopped.
            await answerReleased.waitIgnoringCancellation()
            return try decodeNetworkInfo()
        })
        let run = Task { @MainActor in
            await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(30),
                clock: ManualClock(), defaults: store)
        }
        try await questionEntered.wait()
        session.nodeState = .stopping   // the app stops the node while the question is out
        answerReleased.open()           // the answer lands anyway — and must be discarded
        let report = await run.value
        #expect(report.outcome == .noAnswer)
        #expect(report.blockHeight == nil)
        #expect(NodeViewModel.lastRun(in: store)?.height == 90)
        #expect(NodeViewModel.lastRun(in: store)?.chain == "signet")
        #expect(NodeViewModel.lastKnown(in: store)?.height == 95)
        #expect(NodeViewModel.lastKnown(in: store)?.chain == "signet")
    }

    @Test("the result boundary drops a produced report when the run is cancelled or stopped")
    func resultBoundaryDropsReport() async throws {
        let store = makeVolatileDefaults()
        let measured = NodeRunReport(
            outcome: .started, syncEnding: .notMeasured,
            chain: "main", blockHeight: 110, blocksGainedThisRun: nil,
            dialogTemplate: "Node running.")

        // The last window the checks exist for: the run produced a measured
        // report, then the run was cancelled before it could be returned. The
        // task is cancelled before its body can run — a @MainActor child
        // cannot start until this synchronous stretch yields — so the flag is
        // provably set when the boundary reads it.
        let cancelled = Task { @MainActor in
            try NodeRun.resultUnlessCancelled(measured, into: store)
        }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }

        // The iOS 27 action's stop flag rides beside task cancellation — the
        // same throw, and again nothing persisted.
        #expect(throws: CancellationError.self) {
            try NodeRun.resultUnlessCancelled(measured, wasStopped: true, into: store)
        }

        #expect(NodeViewModel.lastRun(in: store) == nil)
        #expect(NodeViewModel.lastKnown(in: store) == nil)

        // And a report still wanted when it crosses the boundary does return
        // and persist — the gate is not a blanket refusal.
        let kept = try NodeRun.resultUnlessCancelled(measured, into: store)
        #expect(kept.blockHeight == 110)
        #expect(NodeViewModel.lastRun(in: store)?.height == 110)
        #expect(NodeViewModel.lastKnown(in: store)?.height == 110)
    }

    /// A clock nobody advances would pass even if every sleep in the run
    /// went back to `Task.sleep` — the seam would exist and prove nothing.
    /// The recording wrapper is what makes this fail when it should: a nap
    /// spelled `Task.sleep` never asks the injected clock, so the gate never
    /// opens and the limit bites; a deadline measured on the wall clock
    /// outlasts it too — the budget is deliberately longer than the smallest
    /// `.timeLimit`, so only virtual time can finish the run in time.
    @Test(
        "the first-answer wait naps and times out on the injected clock",
        .timeLimit(.minutes(1)))
    func waitRunsOnInjectedClock() async throws {
        let test = ManualClock()
        let start = test.now
        let napRequested = Gate()
        let tolerances = Mutex<[Duration?]>([])
        let clock = ObservedClock(base: test) { deadline, tolerance in
            tolerances.withLock { $0.append(tolerance) }
            // The nap is the only sleep due inside the question's own
            // ten-second bound — the bound's race and the run's deadline
            // both land at or past it.
            if deadline < start.advanced(by: .seconds(10)) {
                napRequested.open()
            }
        }
        let session = FakeRunSession(
            // `.starting` waits on the first answer and skips the
            // device-condition read entirely — no other sleeps in play.
            nodeState: .starting,
            reader: StagedReader(
                blockchain: { throw StagedReader.NotScripted() },
                network: { throw StagedReader.NotScripted() }))
        let run = Task { @MainActor in
            await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                clock: clock, defaults: makeVolatileDefaults())
        }
        try await napRequested.wait()      // the nap asked *this* clock
        // Past the run's deadline — the parked nap wakes and the wait's
        // `now < deadline` check ends the loop.
        test.advance(by: .seconds(241))
        #expect(await run.value.outcome == .didNotComeUp)
        let recorded = tolerances.withLock { $0 }
        #expect(!recorded.isEmpty)
        // Every sleep on this path bounds a deadline — the question race and
        // the capped nap alike — so none carries tolerance.
        #expect(recorded.allSatisfy { $0 == nil })
    }

    /// The other half of the policy: the heartbeat is a cadence, so it
    /// carries the shared tolerance that lets the system coalesce it — but
    /// proportional, capped at a fifth of the interval, so the millisecond
    /// cadences a test drives are not dominated by a flat second. The two
    /// arguments cover both sides of the `min`: a production-sized interval
    /// where the shared constant binds, and a small one where the
    /// proportion does.
    /// `runWithHeartbeat` is iOS 27-only, so the attribute sits on the test —
    /// the same convention `SyncNodeLongRunningIntentTests` uses.
    @available(iOS 27.0, *)
    @Test(
        "the heartbeat sleep carries a tolerance proportional to its interval",
        .timeLimit(.minutes(1)),
        arguments: [
            (interval: Duration.seconds(5), expected: NodeRun.sleepTolerance),
            (interval: .milliseconds(100), expected: .milliseconds(20)),
        ])
    func heartbeatCarriesSharedTolerance(
        interval: Duration, expected: Duration
    ) async throws {
        let heartbeatSlept = Gate()
        let tolerances = Mutex<[Duration?]>([])
        let clock = ObservedClock(base: ManualClock()) { _, tolerance in
            tolerances.withLock { $0.append(tolerance) }
            heartbeatSlept.open()
        }
        let workUnblocked = Gate()
        let meter = ProgressMeter(progress: Progress(), scale: 1)
        let run = Task { @MainActor in
            await SyncNodeLongRunningIntent.runWithHeartbeat(
                meter: meter, clock: clock,
                isStopped: { false }, heartbeatInterval: interval
            ) { _, _ in
                await workUnblocked.waitIgnoringCancellation()
                return NodeRun.noAnswerReport()
            }
        }
        try await heartbeatSlept.wait()
        workUnblocked.open()
        _ = await run.value
        let recorded = tolerances.withLock { $0 }
        #expect(!recorded.isEmpty)
        #expect(recorded.allSatisfy { $0 == expected })
    }

    /// Files the run cannot read must not be prepared either — the folder
    /// prepare is the gather's one write, so the read that gates it has to
    /// come first. The fake records every call, putting the order — not
    /// just the decline — under test.
    @Test(
        "files the run cannot read are never prepared",
        .timeLimit(.minutes(1)))
    func unreadableFilesNeverReachTheFolder() async throws {
        let device = FakeDeviceReadings()
        device.isProtectedDataAvailable = false
        let session = FakeRunSession(
            nodeState: .stopped,
            reader: StagedReader(
                blockchain: { throw StagedReader.NotScripted() },
                network: { throw StagedReader.NotScripted() }),
            device: device)
        let report = await NodeRun.perform(
            session: session, waitForFirstAnswer: .seconds(30),
            clock: ManualClock(), defaults: makeVolatileDefaults())
        #expect(report.outcome == .declined)
        let calls = device.calls.withLock { $0 }
        // The watcher start is the one call that precedes every gather —
        // pinned first here rather than assumed.
        #expect(calls.first == "startWatchingNetworkCost")
        #expect(calls.contains("protectedDataAvailable"))
        #expect(!calls.contains("prepareChainFolder"))
    }

    /// A network that never reports cannot hold the gather open: the bound
    /// fires on the injected clock, the cost falls back to `.unknown`, and
    /// the run carries on to the start. The parked read ignores
    /// cancellation like the production monitor's poll — only the timer
    /// releases the caller.
    @Test(
        "a network that never reports falls back inside the gather's bound",
        .timeLimit(.minutes(1)))
    func networkWaitFallsBackOnBound() async throws {
        let test = ManualClock()
        let gatherStarted = Gate()
        let napRequested = Gate()
        let clock = ObservedClock(base: test) { deadline, _ in
            // The gather's bound asks first; the wait loop's nap is the only
            // sub-second sleep after it — every other bound is whole seconds.
            if test.now.duration(to: deadline) <= .milliseconds(750) {
                napRequested.open()
            } else {
                gatherStarted.open()
            }
        }
        let device = FakeDeviceReadings(firstNetworkReport: {
            await Gate().waitIgnoringCancellation()
            return .unknown  // unreachable — the parked read never answers
        })
        let session = FakeRunSession(
            nodeState: .stopped,
            reader: StagedReader(
                blockchain: { throw StagedReader.NotScripted() },
                network: { throw StagedReader.NotScripted() }),
            device: device)
        session.startNodeResult = true
        let run = Task { @MainActor in
            await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(30),
                clock: clock, defaults: makeVolatileDefaults())
        }
        // The advance has to wait for the bound's request: its deadline is
        // computed from `clock.now` at call time, so a run scheduled after
        // the advance would register a sleep past the last tick and park
        // forever — and this wait would hang beside it.
        try await gatherStarted.wait()
        // Past the gather's two-second bound.
        test.advance(by: .seconds(3))
        try await napRequested.wait()
        // The gather fell back and the run reached the start — provable
        // only through the bound, the parked report never answering.
        #expect(session.startNodeArguments != nil)
        let calls = device.calls.withLock { $0 }
        #expect(before("protectedDataAvailable", "prepareChainFolder", in: calls))
        run.cancel()
        _ = await run.value   // the parked nap throws; the run reports nothing
    }

    /// The per-question transport log exists so a `noProgress` verdict can
    /// attribute timings to the right ceiling — a consult skipped at one
    /// question site is a gap in exactly the trail it builds. The fake
    /// counts every read, so a dropped consult lands as a wrong number.
    @Test("the run consults the serving transport once per question")
    func transportConsultedPerQuestion() async throws {
        let session = sessionAnswering(network: { try decodeNetworkInfo() })
        let report = await NodeRun.perform(
            session: session, waitForFirstAnswer: .seconds(30),
            clock: ManualClock(), defaults: makeVolatileDefaults())
        #expect(report.blockHeight == 100)
        // Two questions — blockchain info, then the peer count — and the
        // flag was consulted once for each.
        #expect(session.bridgeReadyReads == 2)
    }

    /// The answer the fake hands the gather is the one `NodePreflight`
    /// weighs: a metered first report declines the run before it ever asks
    /// for the folder or the daemon.
    @Test(
        "a metered first report declines the run",
        .timeLimit(.minutes(1)))
    func meteredNetworkDeclines() async throws {
        let device = FakeDeviceReadings(firstNetworkReport: {
            NetworkCost(isMetered: true, isDataRestricted: false)
        })
        let session = FakeRunSession(
            nodeState: .stopped,
            reader: StagedReader(
                blockchain: { throw StagedReader.NotScripted() },
                network: { throw StagedReader.NotScripted() }),
            device: device)
        let report = await NodeRun.perform(
            session: session, waitForFirstAnswer: .seconds(30),
            clock: ManualClock(), defaults: makeVolatileDefaults())
        #expect(report.outcome == .declined)
        #expect(session.startNodeArguments == nil)
    }

}

/// FR-013's wait: a run that finds the private network required but not yet
/// usable spends a bounded grace establishing it rather than declining on the
/// spot — then re-decides on live facts: node state, conditions, the step.
/// These tests pin the wait's contract: a network that never arrives keeps
/// the ungraced decline's verdict and wording; one that arrives mid-wait
/// reaches the re-decision and launches; a node moving on its own — started
/// *or* stopped by the person — ends the wait early (a wait that ran on
/// could relaunch a node someone just stopped); and the same verdict
/// reached at the launch boundary lands on the same grace rather than
/// declining out of order. Nothing sleeps real time: the poll naps on the
/// injected `ManualClock` like every wait in this file, and each advance is
/// gated on the nap's request — ordering on the event, never on a guess.
@Suite("Private-network grace")
@MainActor
struct NodeRunGraceTests {

    /// An `ObservedClock` over a fresh `ManualClock`, plus the gate its
    /// reporter opens the first time a sub-second sleep is requested — the
    /// grace poll's nap is the only one this path asks for, where the
    /// gather's two-second bound and every question's are whole seconds.
    private func graceClock() -> (
        test: ManualClock, napRequested: Gate, clock: ObservedClock
    ) {
        let test = ManualClock()
        let napRequested = Gate()
        let clock = ObservedClock(base: test) { deadline, _ in
            if test.now.duration(to: deadline) <= .milliseconds(750) {
                napRequested.open()
            }
        }
        return (test, napRequested, clock)
    }

    @Test(
        "a network that never readies waits out the grace, then declines unchanged",
        .timeLimit(.minutes(1)))
    func neverReadyDeclinesAfterGrace() async throws {
        let clock = graceClock()
        let store = makeVolatileDefaults()
        store.set(true, forKey: "tor_enabled")
        let device = FakeDeviceReadings()
        let session = FakeRunSession(
            nodeState: .stopped,
            reader: StagedReader(
                blockchain: { throw StagedReader.NotScripted() },
                network: { throw StagedReader.NotScripted() }),
            device: device)
        session.torIsComingUp = true   // bootstrapping for as long as the run waits
        session.torStillEnabled = true
        var emitted: [NodeRun.ProgressUpdate] = []
        let done = Gate()
        let run = Task { @MainActor in
            defer { done.open() }
            return await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                privateNetworkGrace: .seconds(90),
                clock: clock.clock, defaults: store) { emitted.append($0) }
        }
        try await clock.napRequested.wait()   // the wait is on the injected clock
        // Stepped advances rather than one jump: each wakes a pass that
        // writes progress and re-naps — the yield runs that enqueued body
        // before the clock moves again, so the ramp is sampled pass by
        // pass. How many turns the run needs per nap is platform-dependent,
        // so the drive is bounded by the run finishing. The cap guards only
        // underdrive — ten 30 s steps are 300 virtual s against the 90 s
        // grace; if all of them land before the run's first wake, the clock
        // is already past the deadline, the wait exits after one write, and
        // the emitted-count assertion below reports it.
        for _ in 0..<10 where !done.isOpen {
            clock.test.advance(by: .seconds(30))
            await Task.yield()
        }
        let report = await run.value
        #expect(report.outcome == .declined)
        // The verdict and its sentence are the ungraced path's, verbatim —
        // the wait changed when the decline lands, not what it says.
        #expect(report.summary.contains("being established"))
        // Nudged once on the way in and once at the re-decision's live check.
        #expect(session.torStartCalls == 2)
        #expect(session.startNodeArguments == nil)
        // The re-decision re-weighed the device conditions — the gather ran
        // once on the way in and once on the way out.
        let calls = device.calls.withLock { $0 }
        #expect(calls.filter { $0 == "networkFirst" }.count == 2)
        // The wait reported throughout: a rising ramp that never left the
        // start-up band — its own share of the bar, leaving the watch's
        // share untouched (FR-004). The floor pins the *single* band: a
        // double-banded write — the hazard the caller's comment names for
        // the day the run-wide wrapper lands — can never exceed
        // bandEnd² (the band applied to the largest possible raw value),
        // while any interval write is ~bandEnd/3 here; unbanded writes
        // would vault the cap. How many interval writes land is the
        // runner's scheduling, so the bound discriminates per write
        // rather than counting them.
        #expect(emitted.count >= 2)
        #expect(emitted.map(\.fraction) == emitted.map(\.fraction).sorted())
        #expect(emitted.allSatisfy {
            $0.fraction <= NodeAutomation.startUpBandEnd
        })
        #expect(
            emitted.map(\.fraction).max() ?? 0
                > NodeAutomation.startUpBandEnd * NodeAutomation.startUpBandEnd)
    }

    @Test(
        "a network readying inside the grace reaches the re-decision and starts",
        .timeLimit(.minutes(1)))
    func readyingReachesStart() async throws {
        let clock = graceClock()
        let store = makeVolatileDefaults()
        store.set(true, forKey: "tor_enabled")
        let session = FakeRunSession(
            nodeState: .stopped,
            reader: StagedReader(
                blockchain: { try decodeBlockchainInfo() },
                network: { try decodeNetworkInfo() }))
        session.torIsComingUp = true
        session.torStillEnabled = true
        session.torProxyAddress = "127.0.0.1:9050"
        session.torSocksPort = 9050
        session.startNodeResult = true
        var emitted: [NodeRun.ProgressUpdate] = []
        let run = Task { @MainActor in
            await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                privateNetworkGrace: .seconds(90),
                clock: clock.clock, defaults: store) { emitted.append($0) }
        }
        try await clock.napRequested.wait()
        // The bootstrap finishes inside the window the run held open for it.
        session.torIsReady = true
        session.torIsComingUp = false
        clock.test.advance(by: .milliseconds(600))
        let report = await run.value
        #expect(report.outcome == .started)
        #expect(report.blockHeight == 100)
        // The re-decision's launch carries the proxy the network offered.
        #expect(
            session.startNodeArguments?.contains { $0.hasPrefix("-proxy=") }
                == true)
        #expect(session.torStartCalls == 1)
        // One scale across the boundary: the grace's ramp and the
        // first-answer ramp both land inside the startup band — the meter
        // floors the dip where a new stage's raw ramp restarts at zero.
        #expect(
            emitted.allSatisfy { $0.fraction <= NodeAutomation.startUpBandEnd })
    }

    /// The boundary the one-scale band exists for: the grace's ramp ends
    /// near the band's top, and the first-answer ramp behind it restarts
    /// from zero — a downward step only the meter's floor hides. A delayed
    /// first answer produces the dip; every emitted write stays inside the
    /// band, and the sequence's downward step is the restart the T034
    /// heartbeat coupling counts on (writes arriving that cannot move the
    /// floored bar).
    @Test(
        "the first-answer ramp restarts below the grace's band — the dip is the meter's to absorb",
        .timeLimit(.minutes(1)))
    func rampRestartsInsideBand() async throws {
        let clock = graceClock()
        let store = makeVolatileDefaults()
        store.set(true, forKey: "tor_enabled")
        let polls = Mutex(0)
        let session = FakeRunSession(
            nodeState: .stopped,
            reader: StagedReader(
                blockchain: {
                    // Two thrown answers buy ~1 s of the ramp's low end
                    // before the real reading lands.
                    let n = polls.withLock { n in
                        n += 1
                        return n
                    }
                    if n <= 2 { throw StagedReader.NotScripted() }
                    return try decodeBlockchainInfo()
                },
                network: { try decodeNetworkInfo() }))
        session.torIsComingUp = true
        session.torStillEnabled = true
        session.torProxyAddress = "127.0.0.1:9050"
        session.torSocksPort = 9050
        session.startNodeResult = true
        var emitted: [NodeRun.ProgressUpdate] = []
        let done = Gate()
        let run = Task { @MainActor in
            defer { done.open() }
            return await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                privateNetworkGrace: .seconds(90),
                clock: clock.clock, defaults: store) { emitted.append($0) }
        }
        try await clock.napRequested.wait()
        // Thirty seconds of grace first — the ramp has somewhere to restart
        // *from* — then the bootstrap finishes inside the held window.
        clock.test.advance(by: .seconds(30))
        await Task.yield()
        session.torIsReady = true
        session.torIsComingUp = false
        clock.test.advance(by: .milliseconds(600))
        // The stretch ahead is a chain of ≤500 ms naps — the gather's
        // bounded wait, the poll's two thrown answers, the final reading —
        // and each woken pass needs executor turns before the clock moves
        // again. How many turns is platform-dependent (a starved simulator
        // needs more than any fixed count), so the drive is bounded by the
        // run finishing or by the virtual budget that bounds it — 600
        // iterations of 600 ms well past the 240 s question deadline.
        // Overdrive ends the wait, not the drive: a run still starved when
        // the clock crosses its deadline reports `.didNotComeUp`, so the
        // `.started` assertion failing without a stall is the starvation
        // signature.
        for _ in 0..<600 where !done.isOpen {
            clock.test.advance(by: .milliseconds(600))
            await Task.yield()
        }
        let report = await run.value
        #expect(report.outcome == .started)
        #expect(
            emitted.allSatisfy { $0.fraction <= NodeAutomation.startUpBandEnd })
        #expect(
            zip(emitted, emitted.dropFirst())
                .contains { $1.fraction < $0.fraction })
    }

    @Test(
        "a node coming up on its own ends the wait early — read, never restarted",
        .timeLimit(.minutes(1)))
    func nodeComingUpEndsWait() async throws {
        let clock = graceClock()
        let store = makeVolatileDefaults()
        store.set(true, forKey: "tor_enabled")
        let session = FakeRunSession(
            nodeState: .stopped,
            reader: StagedReader(
                blockchain: { try decodeBlockchainInfo() },
                network: { try decodeNetworkInfo() }))
        session.torIsComingUp = true
        session.torStillEnabled = true
        let run = Task { @MainActor in
            await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                privateNetworkGrace: .seconds(90),
                clock: clock.clock, defaults: store)
        }
        try await clock.napRequested.wait()
        session.nodeState = .running   // someone else's start landed mid-wait
        clock.test.advance(by: .milliseconds(600))
        let report = await run.value
        #expect(report.outcome == .alreadyRunning)
        #expect(report.blockHeight == 100)
        // Read and left alone — ADR 0005. The wait stopped mattering the
        // moment the node stopped needing it.
        #expect(session.startNodeArguments == nil)
        #expect(session.torStartCalls == 1)
    }

    @Test(
        "a node stopped mid-grace is honored — never relaunched behind the stop",
        .timeLimit(.minutes(1)))
    func nodeStoppingEndsWait() async throws {
        let clock = graceClock()
        let store = makeVolatileDefaults()
        store.set(true, forKey: "tor_enabled")
        let session = FakeRunSession(
            nodeState: .stopped,
            reader: StagedReader(
                blockchain: { try decodeBlockchainInfo() },
                network: { try decodeNetworkInfo() }))
        session.torIsComingUp = true
        session.torStillEnabled = true
        let run = Task { @MainActor in
            await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                privateNetworkGrace: .seconds(90),
                clock: clock.clock, defaults: store)
        }
        try await clock.napRequested.wait()
        session.nodeState = .stopping   // a manual Stop landing mid-wait
        clock.test.advance(by: .milliseconds(600))
        let report = await run.value
        #expect(report.outcome == .noAnswer)
        // The worst answer available — the node relaunched behind the
        // person's stop — is precisely the one that cannot happen.
        #expect(session.startNodeArguments == nil)
    }

    @Test(
        "a network switched off mid-grace declines as turned off",
        .timeLimit(.minutes(1)))
    func turnedOffMidGraceDeclinesOff() async throws {
        let clock = graceClock()
        let store = makeVolatileDefaults()
        store.set(true, forKey: "tor_enabled")
        let session = FakeRunSession(
            nodeState: .stopped,
            reader: StagedReader(
                blockchain: { throw StagedReader.NotScripted() },
                network: { throw StagedReader.NotScripted() }))
        session.torIsComingUp = true
        session.torStillEnabled = true
        let run = Task { @MainActor in
            await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                privateNetworkGrace: .seconds(90),
                clock: clock.clock, defaults: store)
        }
        try await clock.napRequested.wait()
        // The toggle's write — and the teardown it ordered — land mid-wait.
        store.set(false, forKey: "tor_enabled")
        session.torIsComingUp = false
        session.torStillEnabled = false
        clock.test.advance(by: .milliseconds(600))
        let report = await run.value
        #expect(report.outcome == .declined)
        // Nothing is being established — the other sentence, on purpose.
        #expect(report.summary.contains("turned off"))
        #expect(session.torStartCalls == 2)
    }

    @Test(
        "a network that stops coming ends the wait early — nothing left to wait on",
        .timeLimit(.minutes(1)))
    func deadTorEndsWaitEarly() async throws {
        let clock = graceClock()
        let store = makeVolatileDefaults()
        store.set(true, forKey: "tor_enabled")
        let session = FakeRunSession(
            nodeState: .stopped,
            reader: StagedReader(
                blockchain: { throw StagedReader.NotScripted() },
                network: { throw StagedReader.NotScripted() }))
        session.torIsComingUp = true
        session.torStillEnabled = true
        let run = Task { @MainActor in
            await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                privateNetworkGrace: .seconds(90),
                clock: clock.clock, defaults: store)
        }
        try await clock.napRequested.wait()
        // The backoff schedule ran out: the toggle is still on but nothing
        // is on its way anymore. A wait that ignored this would burn the
        // rest of the budget on a dead network — the small advance below
        // finishes only because the pass reads the flag and lets go.
        session.torIsComingUp = false
        clock.test.advance(by: .milliseconds(600))
        let report = await run.value
        #expect(report.outcome == .declined)
        // Out of budget, the re-decision's verdict is the ungraced one —
        // nudge and decline, in its own words.
        #expect(report.summary.contains("being established"))
        #expect(session.torStartCalls == 2)
        #expect(session.startNodeArguments == nil)
    }

    /// The step is weighed on the *snapshot's* privacy setting while the
    /// launch boundary re-reads the live one — the one door where the two
    /// disagree. A toggle flipped on inside the gather's suspension window
    /// throws `.privateNetworkNotReady` at the boundary, and the verdict
    /// must route through the wait-or-decline machinery exactly once: a
    /// catch that merely retried the identical `.startNode` step would
    /// spin on it forever — the shipped shape before the stall was marked.
    /// `.timeLimit` is the assertion: unfixed, this test does not fail, it
    /// hangs.
    @Test(
        "a privacy toggle flipped on mid-gather stalls once, then declines",
        .timeLimit(.minutes(1)))
    func toggleOnMidGatherDeclinesOnce() async throws {
        let gatherParked = Gate()
        let gatherRelease = Gate()
        let store = makeVolatileDefaults()
        // The snapshot enters with privacy OFF — the step reads `.startNode`
        // and the toggle lands while the first gather is parked.
        let device = FakeDeviceReadings(firstNetworkReport: {
            gatherParked.open()
            await gatherRelease.waitIgnoringCancellation()
            return NetworkCost(isMetered: false, isDataRestricted: false)
        })
        let session = FakeRunSession(
            nodeState: .stopped,
            reader: StagedReader(
                blockchain: { throw StagedReader.NotScripted() },
                network: { throw StagedReader.NotScripted() }),
            device: device)
        session.torStillEnabled = true
        // No grace — the shape both shipped actions run today.
        let run = Task { @MainActor in
            await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(30),
                clock: ManualClock(), defaults: store)
        }
        try await gatherParked.wait()
        store.set(true, forKey: "tor_enabled")   // flipped on inside the window
        gatherRelease.open()
        let report = await run.value
        #expect(report.outcome == .declined)
        #expect(report.summary.contains("being established"))
        #expect(session.startNodeArguments == nil)
        #expect(session.torStartCalls == 1)
        // Two passes, two gathers: the start attempt, then the
        // wait-or-decline re-decision the stall was carried into.
        let calls = device.calls.withLock { $0 }
        #expect(calls.filter { $0 == "networkFirst" }.count == 2)
    }

    /// The same flipped-on stall, graced: the routed verdict spends the one
    /// budget like any other not-ready outcome, then declines unchanged.
    @Test(
        "a privacy toggle flipped on mid-gather spends the grace, then declines",
        .timeLimit(.minutes(1)))
    func toggleOnMidGatherSpendsGrace() async throws {
        let clock = graceClock()
        let gatherParked = Gate()
        let gatherRelease = Gate()
        let store = makeVolatileDefaults()
        let device = FakeDeviceReadings(firstNetworkReport: {
            gatherParked.open()
            await gatherRelease.waitIgnoringCancellation()
            return NetworkCost(isMetered: false, isDataRestricted: false)
        })
        let session = FakeRunSession(
            nodeState: .stopped,
            reader: StagedReader(
                blockchain: { throw StagedReader.NotScripted() },
                network: { throw StagedReader.NotScripted() }),
            device: device)
        session.torIsComingUp = true
        session.torStillEnabled = true
        let run = Task { @MainActor in
            await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                privateNetworkGrace: .seconds(90),
                clock: clock.clock, defaults: store)
        }
        try await gatherParked.wait()
        store.set(true, forKey: "tor_enabled")
        gatherRelease.open()
        // The stall routed into the wait — the nap opening proves it.
        try await clock.napRequested.wait()
        clock.test.advance(by: .seconds(91))
        let report = await run.value
        #expect(report.outcome == .declined)
        #expect(report.summary.contains("being established"))
        #expect(session.torStartCalls == 2)
        #expect(session.startNodeArguments == nil)
    }

    @Test(
        "a network dropping inside the condition window lands on the same grace",
        .timeLimit(.minutes(1)))
    func launchBoundaryDropEntersGrace() async throws {
        let clock = graceClock()
        let gatherParked = Gate()
        let gatherRelease = Gate()
        let store = makeVolatileDefaults()
        store.set(true, forKey: "tor_enabled")
        let device = FakeDeviceReadings(firstNetworkReport: {
            gatherParked.open()
            await gatherRelease.waitIgnoringCancellation()
            return NetworkCost(isMetered: false, isDataRestricted: false)
        })
        let session = FakeRunSession(
            nodeState: .stopped,
            reader: StagedReader(
                blockchain: { try decodeBlockchainInfo() },
                network: { try decodeNetworkInfo() }),
            device: device)
        // Privacy is ready when the step is weighed — the drop lands while
        // the gather is suspended, the second door to the same verdict.
        session.torIsReady = true
        session.torProxyAddress = "127.0.0.1:9050"
        session.torSocksPort = 9050
        session.torStillEnabled = true
        session.startNodeResult = true
        let run = Task { @MainActor in
            await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                privateNetworkGrace: .seconds(90),
                clock: clock.clock, defaults: store)
        }
        try await gatherParked.wait()
        session.torIsReady = false
        session.torIsComingUp = true
        gatherRelease.open()
        // A declined report would already exist by now — the nap opening
        // proves the refusal routed into the wait instead.
        try await clock.napRequested.wait()
        session.torIsReady = true
        session.torIsComingUp = false
        clock.test.advance(by: .milliseconds(600))
        let report = await run.value
        #expect(report.outcome == .started)
        #expect(
            session.startNodeArguments?.contains { $0.hasPrefix("-proxy=") }
                == true)
        #expect(session.torStartCalls == 1)
    }

    @Test(
        "a run cancelled inside the grace reports nothing",
        .timeLimit(.minutes(1)))
    func cancelInsideGraceReportsNothing() async throws {
        let clock = graceClock()
        let store = makeVolatileDefaults()
        store.set(true, forKey: "tor_enabled")
        let session = FakeRunSession(
            nodeState: .stopped,
            reader: StagedReader(
                blockchain: { throw StagedReader.NotScripted() },
                network: { throw StagedReader.NotScripted() }))
        session.torIsComingUp = true
        session.torStillEnabled = true
        let run = Task { @MainActor in
            await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                privateNetworkGrace: .seconds(90),
                clock: clock.clock, defaults: store)
        }
        try await clock.napRequested.wait()
        run.cancel()
        // Wake the nap whether or not the sleep itself observes the cancel —
        // the pass-top check catches it either way.
        clock.test.advance(by: .milliseconds(600))
        let report = await run.value
        #expect(report.outcome == .noAnswer)
        #expect(session.startNodeArguments == nil)
    }

    /// The marker is spent once: a network that readied inside the grace,
    /// reached the launch boundary a second time, and dropped inside that
    /// gather's window too, declines the unchanged verdict rather than
    /// buying another trip. The second stall is not a hypothetical — the
    /// re-decided step is `.startNode` while the network reports ready, so
    /// a repeat flap lands on the same door; `guard !networkStalled` is
    /// the bound there, and this is the only test that can see it work.
    @Test(
        "a second boundary stall declines — the marker is spent once",
        .timeLimit(.minutes(1)))
    func secondStallDeclines() async throws {
        let clock = graceClock()
        let firstGatherParked = Gate()
        let firstGatherRelease = Gate()
        let thirdGatherParked = Gate()
        let thirdGatherRelease = Gate()
        let gatherCalls = Mutex(0)
        let store = makeVolatileDefaults()
        store.set(true, forKey: "tor_enabled")
        // Gathers 1 and 3 park — the two windows a drop lands inside.
        let device = FakeDeviceReadings(firstNetworkReport: {
            let n = gatherCalls.withLock { c -> Int in c += 1; return c }
            if n == 1 {
                firstGatherParked.open()
                await firstGatherRelease.waitIgnoringCancellation()
            }
            if n == 3 {
                thirdGatherParked.open()
                await thirdGatherRelease.waitIgnoringCancellation()
            }
            return NetworkCost(isMetered: false, isDataRestricted: false)
        })
        let session = FakeRunSession(
            nodeState: .stopped,
            reader: StagedReader(
                blockchain: { throw StagedReader.NotScripted() },
                network: { throw StagedReader.NotScripted() }),
            device: device)
        // Ready when the step is weighed — the first drop lands inside
        // gather 1's window.
        session.torIsReady = true
        session.torProxyAddress = "127.0.0.1:9050"
        session.torSocksPort = 9050
        session.torStillEnabled = true
        let run = Task { @MainActor in
            await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(30),
                privateNetworkGrace: .seconds(90),
                clock: clock.clock, defaults: store)
        }
        try await firstGatherParked.wait()
        session.torIsReady = false
        session.torIsComingUp = true
        firstGatherRelease.open()
        // The stall routed into the wait — the nap opening proves it. The
        // network readies inside the grace, reaching the re-decision.
        try await clock.napRequested.wait()
        session.torIsReady = true
        session.torIsComingUp = false
        clock.test.advance(by: .milliseconds(600))
        // The re-decision's `.startNode` runs its own gather — the second
        // drop lands inside its window, and the boundary throws again.
        try await thirdGatherParked.wait()
        session.torIsReady = false
        thirdGatherRelease.open()
        let report = await run.value
        #expect(report.outcome == .declined)
        // The verdict is the stall's own sentence — unchanged from the
        // first time the boundary measured it.
        #expect(report.summary.contains("being established"))
        #expect(session.startNodeArguments == nil)
        #expect(session.torStartCalls == 1)
        #expect(gatherCalls.withLock { $0 } == 3)
    }

    /// A stall-routed pass re-decides on live facts — device conditions
    /// included. A link turning metered between the boundary's throw and
    /// the re-decision's gather reports the refusal now standing in the
    /// way, not the privacy sentence it displaced.
    @Test(
        "a condition turning refusing after a stall reports the device refusal",
        .timeLimit(.minutes(1)))
    func stallReWeighsConditions() async throws {
        let gatherParked = Gate()
        let gatherRelease = Gate()
        let gatherCalls = Mutex(0)
        let store = makeVolatileDefaults()
        store.set(true, forKey: "tor_enabled")
        // The first gather is permissive and parked; the stall's
        // re-decision gather reports the metered link that replaced it.
        let device = FakeDeviceReadings(firstNetworkReport: {
            let n = gatherCalls.withLock { c -> Int in c += 1; return c }
            if n == 1 {
                gatherParked.open()
                await gatherRelease.waitIgnoringCancellation()
                return NetworkCost(isMetered: false, isDataRestricted: false)
            }
            return NetworkCost(isMetered: true, isDataRestricted: false)
        })
        let session = FakeRunSession(
            nodeState: .stopped,
            reader: StagedReader(
                blockchain: { throw StagedReader.NotScripted() },
                network: { throw StagedReader.NotScripted() }),
            device: device)
        // Ready when the step is weighed — the drop lands inside the
        // gather's window, so the launch boundary throws the stall.
        session.torIsReady = true
        session.torProxyAddress = "127.0.0.1:9050"
        session.torSocksPort = 9050
        session.torStillEnabled = true
        let run = Task { @MainActor in
            await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(30),
                privateNetworkGrace: .seconds(90),
                clock: ManualClock(), defaults: store)
        }
        try await gatherParked.wait()
        session.torIsReady = false
        gatherRelease.open()
        let report = await run.value
        #expect(report.outcome == .declined)
        // The verdict is the condition now in the way — the privacy
        // sentence the stall displaced never reaches the person.
        #expect(report.summary.contains("metered"))
        #expect(!report.summary.contains("being established"))
        #expect(session.startNodeArguments == nil)
        #expect(session.torStartCalls == 0)
        #expect(gatherCalls.withLock { $0 } == 2)
    }

    /// A network that is still coming but cannot attempt again inside the
    /// grace reads the same as one that stopped coming at all: the wait
    /// ends on its first pass — no nap is ever requested — and the verdict
    /// is the unchanged decline. The retry's scheduled time is the
    /// horizon-aware reading of "still coming" (`nextRetryAt`'s wall time
    /// against the waiter's remaining budget); a delay that fits keeps the
    /// wait open — `neverReadyDeclinesAfterGrace` holds for the whole
    /// budget precisely because its network has no such deadline.
    @Test(
        "a retry scheduled past the deadline ends the wait early — it cannot arrive in time",
        .timeLimit(.minutes(1)))
    func retryBeyondDeadlineEndsWait() async throws {
        let clock = graceClock()
        let store = makeVolatileDefaults()
        store.set(true, forKey: "tor_enabled")
        let session = FakeRunSession(
            nodeState: .stopped,
            reader: StagedReader(
                blockchain: { throw StagedReader.NotScripted() },
                network: { throw StagedReader.NotScripted() }))
        // Two failures deep in the backoff schedule: the third leg sits
        // 120 s out — beyond any 90 s grace.
        session.torIsComingUp = true
        session.torRetryDelay = .seconds(120)
        session.torStillEnabled = true
        let run = Task { @MainActor in
            await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(30),
                privateNetworkGrace: .seconds(90),
                clock: clock.clock, defaults: store)
        }
        // No nap is ever requested: the wait's first pass reads the
        // attempt's own schedule and lets go. `run.value` returning is the
        // assertion — a wait that held would park forever on a clock that
        // never advances.
        let report = await run.value
        #expect(report.outcome == .declined)
        #expect(report.summary.contains("being established"))
        #expect(session.torStartCalls == 2)
        #expect(session.startNodeArguments == nil)
    }

    /// The seam can report what production's session cannot — a network
    /// marked ready with no usable proxy behind it. A not-ready refusal
    /// landing *while ready* is contradictory rather than transient: the
    /// wait cannot fix it, so it declines on the spot instead of re-trying
    /// the step that produced it.
    @Test(
        "a refusal while the network still reports ready declines — no wait can fix it",
        .timeLimit(.minutes(1)))
    func readyWithoutProxyDeclines() async {
        let store = makeVolatileDefaults()
        store.set(true, forKey: "tor_enabled")
        let session = FakeRunSession(
            nodeState: .stopped,
            reader: StagedReader(
                blockchain: { throw StagedReader.NotScripted() },
                network: { throw StagedReader.NotScripted() }))
        session.torIsReady = true
        session.torProxyAddress = nil   // ready, but nothing usable to bind
        session.torStillEnabled = true
        let report = await NodeRun.perform(
            session: session, waitForFirstAnswer: .seconds(30),
            privateNetworkGrace: .seconds(90),
            clock: ManualClock(), defaults: store)
        #expect(report.outcome == .declined)
        #expect(report.summary.contains("being established"))
        #expect(session.startNodeArguments == nil)
        // No nudge, no wait — the contradictory verdict never reached either.
        #expect(session.torStartCalls == 0)
    }

    /// The ungraced shape is the short action's: no grace budget means the
    /// old verdict — nudge the network and decline on the spot. A regression
    /// pin rather than a new behavior: it must stay green through the change.
    @Test("an ungraced run declines on the spot — the short action is unchanged")
    func ungracedDeclinesOnTheSpot() async {
        let store = makeVolatileDefaults()
        store.set(true, forKey: "tor_enabled")
        let session = FakeRunSession(
            nodeState: .stopped,
            reader: StagedReader(
                blockchain: { throw StagedReader.NotScripted() },
                network: { throw StagedReader.NotScripted() }))
        session.torIsComingUp = true
        session.torStillEnabled = true
        let report = await NodeRun.perform(
            session: session, waitForFirstAnswer: .seconds(30),
            clock: ManualClock(), defaults: store)
        #expect(report.outcome == .declined)
        #expect(report.summary.contains("being established"))
        #expect(session.torStartCalls == 1)
    }
}

/// A `getblockchaininfo` answer mid-IBD — the same shape the production
/// reader returns; the run weighs `chain` and `blocks`. File scope, not a
/// suite member, so the `@Sendable` closures running inside the question
/// bound can reach it without hopping actors.
private func decodeBlockchainInfo() throws -> BlockchainInfo {
    try JSONDecoder().decode(
        BlockchainInfo.self,
        from: Data(
            """
            {"chain":"signet","blocks":100,"headers":200,
             "bestblockhash":"0000000000000000000000000000000000000000000000000000000000000abc",
             "difficulty":1.0,"time":1713300000,"mediantime":1713299990,
             "verificationprogress":0.5,"initialblockdownload":true,
             "chainwork":"0000000000000000000000000000000000000000000000000000000000000192",
             "size_on_disk":12345,"pruned":false,"warnings":[]}
            """.utf8))
}

/// A `getnetworkinfo` answer reporting two connections — the count the
/// run's last question is for; the rest exist because the decoder
/// requires them.
private func decodeNetworkInfo() throws -> NetworkInfo {
    try JSONDecoder().decode(
        NetworkInfo.self,
        from: Data(
            """
            {"version":270000,"subversion":"/Satoshi:29.0.0/","protocolversion":70016,
             "localservices":"0000000000000409","localservicesnames":["NETWORK","WITNESS"],
             "localrelay":true,"timeoffset":0,"networkactive":true,
             "connections":2,"connections_in":0,"connections_out":2,
             "networks":[],"relayfee":0.00001,"incrementalfee":0.00001,
             "localaddresses":[],"warnings":[]}
            """.utf8))
}

/// The session the run asks, scripted: node state is a plain field so a test
/// can stop the node while a question is in flight — something a real
/// `NodeSession` cannot be made to do — and every answer comes from stored
/// values rather than a controller.
@MainActor
private final class FakeRunSession: RunSession {
    var nodeState: NodeState
    var torIsReady = false
    /// The scripted value behind `torIsComingUp(within:)` — `false` by
    /// default, the "dead Tor" reading; a test that wants the wait to hold
    /// scripts `true`.
    var torIsComingUp = false
    /// The scripted delay to the next scheduled attempt, or `nil` for an
    /// attempt already in flight — a horizon-aware reading answers false
    /// only for a delay that outlasts the wait's remaining budget.
    var torRetryDelay: Duration?
    func torIsComingUp(within horizon: Duration) -> Bool {
        torIsComingUp && (torRetryDelay.map { $0 <= horizon } ?? true)
    }
    var torProxyAddress: String?
    var torSessionID: UUID?
    var torSocksPort: UInt16?
    var torStillEnabled = false
    var torStartCalls = 0
    var startNodeResult = false
    var startNodeArguments: [String]?
    let reader: any DashboardDataSource
    /// The concrete fake beside the protocol member — an existential cannot
    /// witness `device` typed `any DeviceReadings`, so the scripted fields a
    /// test flips mid-run live here and the run asks through the getter.
    let deviceReadings: FakeDeviceReadings
    var device: any DeviceReadings { deviceReadings }

    /// The scripted value behind `bridgeReady`; every read is counted so a
    /// test can pin "the run consults the transport once per question" —
    /// the consult itself is the only observable part of the log it feeds.
    var scriptedBridgeReady = false
    private(set) var bridgeReadyReads = 0
    var bridgeReady: Bool {
        bridgeReadyReads += 1
        return scriptedBridgeReady
    }

    init(
        nodeState: NodeState, reader: any DashboardDataSource,
        device: FakeDeviceReadings = FakeDeviceReadings()
    ) {
        self.nodeState = nodeState
        self.reader = reader
        self.deviceReadings = device
    }

    func startNode(
        arguments: [String], torSession: UUID?, torSocksPort: UInt16?
    ) -> Bool {
        startNodeArguments = arguments
        // A successful start moves the node toward `.starting` — leaving the
        // state at `.stopped` would read as "stopped mid-run" to the wait's
        // still-wanted check and end the run early.
        if startNodeResult { nodeState = .starting }
        return startNodeResult
    }

    @discardableResult
    func startTorIfStillEnabled(reading defaults: UserDefaults) -> Bool {
        torStartCalls += 1
        return torStillEnabled
    }
}

/// A `DashboardDataSource` whose answers are scripted per question — staged,
/// parked on gates, or failed — while a question the run never asks reports
/// "not part of this test" rather than inventing a reading.
private struct StagedReader: DashboardDataSource {
    /// Thrown by a question the test did not script: an unexpected call fails
    /// the question instead of answering with an invented reading.
    struct NotScripted: Error {}

    let blockchain: @Sendable () async throws -> BlockchainInfo
    let network: @Sendable () async throws -> NetworkInfo

    func blockchainInfo() async throws -> BlockchainInfo { try await blockchain() }
    func peers() async throws -> [PeerInfo] { throw NotScripted() }
    func mempoolInfo() async throws -> MempoolInfo { throw NotScripted() }
    func networkInfo() async throws -> NetworkInfo { try await network() }
}

/// The device readings, scripted field by field — the seam's other half.
/// Defaults are permissive (files readable, folder there, network cheap,
/// plenty of disk) so a test that never consults conditions needs no setup;
/// a start-path test can park `firstNetworkReport` to drive the gather's
/// bounded wait, or flip a field while the run is in flight.
///
/// The reads whose order the run relies on are recorded in `calls`, in the
/// order made — a test pinning "files were checked before the folder was
/// prepared" compares positions in that list rather than inferring order
/// from side effects. The later-condition fields (`lowPowerModeEnabled`,
/// `thermalState`, `networkCurrent`) stay plain: nothing yet weighs their
/// order.
@MainActor
private final class FakeDeviceReadings: DeviceReadings {
    /// Each `DeviceReadings` member name, in the order the run read it —
    /// a `Mutex` because `networkFirst` deliberately reads off-actor.
    let calls = Mutex<[String]>([])

    var startWatchingCalls = 0
    /// The scripted value behind `protectedDataAvailable`; the read itself
    /// is recorded, which is what lets the ordering tests see it.
    var isProtectedDataAvailable = true
    var lowPowerModeEnabled = false
    var thermalState: ProcessInfo.ThermalState = .nominal
    var chainFolderPrepared = true
    var freeDiskBytesResult: Int64? = 1 << 40
    var networkCurrent: NetworkCost = .unknown
    /// A `let`, not a `var`: `networkFirst` is `nonisolated` to stay off the
    /// main actor like the production read, and only an immutable member is
    /// reachable without the hop a `var` would force.
    let firstNetworkReport: @Sendable () async -> NetworkCost

    /// `nonisolated` so `FakeRunSession(device:)`'s default value — evaluated
    /// at a nonisolated call site — may construct one.
    nonisolated init(
        firstNetworkReport: @escaping @Sendable () async -> NetworkCost = {
            NetworkCost(isMetered: false, isDataRestricted: false)
        }
    ) {
        self.firstNetworkReport = firstNetworkReport
    }

    var protectedDataAvailable: Bool {
        calls.withLock { $0.append("protectedDataAvailable") }
        return isProtectedDataAvailable
    }

    func startWatchingNetworkCost() {
        startWatchingCalls += 1
        calls.withLock { $0.append("startWatchingNetworkCost") }
    }

    func prepareChainFolder() -> Bool {
        calls.withLock { $0.append("prepareChainFolder") }
        return chainFolderPrepared
    }

    func freeDiskBytes() -> Int64? {
        calls.withLock { $0.append("freeDiskBytes") }
        return freeDiskBytesResult
    }

    nonisolated func networkFirst() async -> NetworkCost {
        calls.withLock { $0.append("networkFirst") }
        return await firstNetworkReport()
    }
}

/// Whether `a` precedes `b` in a recorded call list — false when either was
/// never called, so a missing read fails the expectation rather than
/// crashing on a force-unwrap.
private func before(_ a: String, _ b: String, in calls: [String]) -> Bool {
    guard let first = calls.firstIndex(of: a),
          let second = calls.firstIndex(of: b) else { return false }
    return first < second
}

/// Forwards to a `ManualClock`, reporting each sleep request — and its
/// tolerance — before it parks. The oracle for "this wait asked the injected
/// clock": a sleep spelled `Task.sleep` or a deadline measured on
/// `ContinuousClock.now` never reaches this wrapper, which is what lets a
/// test prove the seam is wired rather than merely present.
private struct ObservedClock: Clock {
    typealias Instant = ManualClock.Instant
    let base: ManualClock
    let onSleep: @Sendable (Instant, Duration?) -> Void
    var now: Instant { base.now }
    var minimumResolution: Duration { base.minimumResolution }
    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        onSleep(deadline, tolerance)
        try await base.sleep(until: deadline, tolerance: tolerance)
    }
}

#endif
