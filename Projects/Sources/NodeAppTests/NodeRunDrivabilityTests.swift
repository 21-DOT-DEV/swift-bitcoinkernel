//
//  NodeRunDrivabilityTests.swift
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

    /// The same closing claim on the run's other two unbudgeted landings:
    /// `start`'s site after a stopped node comes up, `waitForStarting`'s
    /// after a starting one answers. `progressReportsArriveAsUpdates` pins
    /// `report`'s exactly; these two assert only the tail — the ramp's
    /// intermediate writes are scheduling-shaped, the closing `1` is the
    /// contract `completionWrite` carries. Dropped to `nil` there, the run
    /// ends claiming nine-tenths — the short action's start path never
    /// showing a full bar.
    @Test(
        "the closing bar-fill claim lands on every unbudgeted landing",
        arguments: [NodeState.stopped, .starting])
    func unbudgetedLandingsClaimTheBar(nodeState: NodeState) async throws {
        let session = FakeRunSession(
            nodeState: nodeState,
            reader: StagedReader(
                blockchain: { try decodeBlockchainInfo() },
                network: { try decodeNetworkInfo() }))
        // Consulted only by the `.stopped` path — a `.starting` session is
        // already past the launch gate.
        session.startNodeResult = true
        var emitted: [NodeRun.ProgressUpdate] = []
        let report = await NodeRun.perform(
            session: session, waitForFirstAnswer: .seconds(30),
            clock: ManualClock(),
            defaults: makeVolatileDefaults(distinguisher: nodeState.rawValue)
        ) { emitted.append($0) }
        #expect(report.outcome == (nodeState == .stopped ? .started : .alreadyRunning))
        #expect(report.blockHeight == 100)
        #expect(emitted.map(\.fraction) == emitted.map(\.fraction).sorted())
        #expect(emitted.last?.fraction == 1)
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
        var emitted: [NodeRun.ProgressUpdate] = []
        let run = Task { @MainActor in
            await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(30),
                clock: ManualClock(), defaults: store) { emitted.append($0) }
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
        // Nor does the emitted trace claim a finish the report doesn't:
        // question milestones only, no closing `1` from a cancelled run.
        #expect(emitted.map(\.fraction) == [0.1, 0.6])
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
        var emitted: [NodeRun.ProgressUpdate] = []
        let run = Task { @MainActor in
            await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(30),
                clock: ManualClock(), defaults: store) { emitted.append($0) }
        }
        try await questionEntered.wait()
        session.nodeState = .stopping   // the app stops the node while the question is out
        answerReleased.open()           // the answer lands anyway — and must be discarded
        let report = await run.value
        #expect(report.outcome == .noAnswer)
        // Same honesty pin as the cancellation case: a discarded reading
        // must not emit the bar-fill claim a measured run earns.
        #expect(emitted.map(\.fraction) == [0.1, 0.6])
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

#endif
