//
//  NodeRunGraceTests.swift
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

/// FR-013's wait: a run that finds the private network required but not yet
/// usable spends a bounded grace establishing it rather than declining on the
/// spot — then re-decides on live facts: node state, conditions, the step.
/// These tests pin the wait's contract: a network that never arrives keeps
/// the ungraced decline's verdict and wording; one that arrives mid-wait
/// reaches the re-decision and launches; a node moving on its own — started
/// *or* stopped by the person — ends the wait early (a wait that ran on
/// could relaunch a node someone just stopped); and the same verdict
/// reached at the launch boundary lands on the same grace rather than
/// declining out of order. The waits under test nap only on the injected
/// `ManualClock`, and each advance fires the earliest armed deadline —
/// capped at the call's step, so a bound armed over work still in flight
/// is approached in hops that buy it real executor turns, never jumped to
/// outright. Each hop then spends a bounded real-time window on the real
/// clock so the in-flight work can take its turns; `.timeLimit` is the
/// backstop that cancels a wedged drive's wait.
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
        // The drive ends only when the run does — the clock crossing the
        // 90 s grace deadline is what ends the wait. Each hop fires the
        // earliest armed deadline capped at 100 ms: naps wake at their own
        // instants so the ramp is sampled pass by pass, and a bound armed
        // over work still in flight is approached in ~20–900 hops of
        // budget — real turns the work needs before the bound can fire.
        try await clock.test.drive(untilDone: done, by: .milliseconds(100))
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
        let graceRamp = Gate()
        let done = Gate()
        let run = Task { @MainActor in
            defer { done.open() }
            return await NodeRun.perform(
                session: session, waitForFirstAnswer: .seconds(240),
                privateNetworkGrace: .seconds(90),
                clock: clock.clock, defaults: store) {
                emitted.append($0)
                // The wait's first pass writes the band's own zero; the
                // post-jump pass is the first strictly-above write — the
                // predicate asks the band itself rather than assuming
                // `startUpBand(0) == 0` forever.
                if $0.fraction > NodeAutomation.startUpBand(0) {
                    graceRamp.open()
                }
            }
        }
        try await clock.napRequested.wait()
        // Thirty seconds of grace first — the ramp has somewhere to restart
        // *from* — then the bootstrap finishes inside the held window. The
        // flip waits on the moved-ramp emission rather than a yield: a pass
        // that wakes to `torIsReady` exits without writing, so ending the
        // wait before the ramp write landed would leave nothing above the
        // restart for the dip below to measure against.
        clock.test.advance(by: .seconds(30))
        try await graceRamp.wait()
        session.torIsReady = true
        session.torIsComingUp = false
        clock.test.advance(by: .milliseconds(600))
        // The stretch ahead is a chain of ≤500 ms poll naps under the
        // gather's 2 s and each question's 10 s bounds — the poll's two
        // thrown answers, then the final reading. The drive fires each
        // armed deadline at its own instant, capped at 100 ms per hop —
        // ~20 turns for the gather's bound, ~100 for a question's — so a
        // bound armed while its work is still in flight is approached in
        // hops that buy the work real turns before it can fire. A run
        // still starved when the clock crosses its 240 s deadline reports
        // `.didNotComeUp` — the `.started` assertion failing without a
        // stall is the starvation signature.
        try await clock.test.drive(untilDone: done, by: .milliseconds(100))
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

#endif
