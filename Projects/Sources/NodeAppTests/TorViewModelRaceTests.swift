//
//  TorViewModelRaceTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Clocks
import Foundation
import Testing
import Tor
@testable import NodeApp

// Shared helpers (`FakeTorSession`, `SessionFactory`) live in
// `Sources/SharedTests/` and are compiled directly into this target — see
// `Projects/Project.swift`. These suites are deterministic by construction:
// retry backoff runs on an injected `TestClock` the test advances, and the
// view model's `awaitSettled()` / `awaitStopped()` hooks let a test await the
// lifecycle task instead of polling `@Observable` state. No `waitFor`, no fixed
// `Task.sleep` — `.starting` and `sessionID` are read synchronously because
// `performStart` sets them before `start()`/`retry()` returns.

// MARK: - Race + retry tests

@Suite("TorViewModel race conditions", .serialized)
@MainActor
struct TorViewModelRaceTests {

    // MARK: - Rapid toggle (§2)

    @Test("stop() during in-flight start() transitions to .disabled")
    func stopCancelsInFlightStart() async throws {
        let fake = FakeTorSession()
        let vm = TorViewModel(
            subsystem: "test",
            backoffSchedule: [.milliseconds(10)],
            makeSession: { _ in fake }
        )

        vm.start()
        #expect(vm.displayState == .starting)

        vm.stop()
        await vm.awaitStopped()

        #expect(vm.displayState == .disabled)
        #expect(vm.socksEndpoint == nil)
        #expect(await fake.stopCalled == true)
    }

    @Test("Cancelled start Task does NOT set .running even if bootstrap completes")
    func cancelledStartDoesNotClobberState() async throws {
        let fake = FakeTorSession()
        let vm = TorViewModel(
            subsystem: "test",
            backoffSchedule: [.milliseconds(10)],
            makeSession: { _ in fake }
        )

        vm.start()
        #expect(vm.displayState == .starting)

        vm.stop()
        await fake.releaseBootstrap()   // bootstrap "completes" — but the start task was cancelled
        await vm.awaitStopped()

        #expect(vm.displayState == .disabled)
        #expect(vm.socksEndpoint == nil)
    }

    @Test("Double stop() is idempotent")
    func doubleStopIsIdempotent() async throws {
        let fake = FakeTorSession()
        let vm = TorViewModel(
            subsystem: "test",
            backoffSchedule: [.milliseconds(10)],
            makeSession: { _ in fake }
        )

        vm.start()
        #expect(vm.displayState == .starting)
        vm.stop()
        vm.stop()
        await vm.awaitStopped()

        #expect(vm.displayState == .disabled)
    }

    @Test("Rapid toggle OFF→ON during .stopping queues restart")
    func rapidToggleQueuesRestart() async throws {
        let factory = SessionFactory([FakeTorSession(), FakeTorSession()])
        let vm = TorViewModel(
            subsystem: "test",
            backoffSchedule: [.milliseconds(10)],
            makeSession: factory.make()
        )

        vm.start()
        #expect(vm.displayState == .starting)
        vm.stop()               // enters .stopping
        vm.start()              // queued (displayState is .stopping)

        // The stop task fires the queued start() on completion, creating a
        // SECOND session. awaitStopped() awaits that teardown (and the restart
        // it triggers), so the count is exact — no settle window, no overshoot.
        await vm.awaitStopped()

        #expect(factory.callCount == 2)
        #expect(vm.displayState == .starting || vm.displayState == .running)
    }

    @Test("Rapid toggle OFF→ON→OFF lands in .disabled")
    func rapidToggleOffOnOff() async throws {
        let factory = SessionFactory([FakeTorSession(), FakeTorSession()])
        let vm = TorViewModel(
            subsystem: "test",
            backoffSchedule: [.milliseconds(10)],
            makeSession: factory.make()
        )

        vm.start()
        #expect(vm.displayState == .starting)
        vm.stop()               // .stopping
        vm.start()              // pending = true
        vm.stop()               // pending cleared
        await vm.awaitStopped()

        #expect(vm.displayState == .disabled)
    }

    @Test("start() failure surfaces as .failed, not .running")
    func startFailureSetsFailed() async throws {
        let vm = TorViewModel(
            subsystem: "test",
            backoffSchedule: [.milliseconds(10)],
            clock: TestClock(),   // the retry parks on virtual time we never advance, so failureCount stays 1
            makeSession: { _ in FakeTorSession(mode: .startThrows) }
        )

        vm.start()
        await vm.awaitSettled()

        #expect(vm.displayState == .failed)
        #expect(vm.socksEndpoint == nil)
        #expect(vm.failureCount == 1)
    }

    @Test("Calling start() from .starting is ignored")
    func startFromStartingIsIgnored() async throws {
        let fake = FakeTorSession()
        let vm = TorViewModel(
            subsystem: "test",
            backoffSchedule: [.milliseconds(10)],
            makeSession: { _ in fake }
        )

        vm.start()
        #expect(vm.displayState == .starting)

        vm.start()
        #expect(vm.displayState == .starting)   // second start() from .starting is ignored

        vm.stop()
        await vm.awaitStopped()
        #expect(vm.displayState == .disabled)
    }

    @Test("stop() from .disabled is a no-op")
    func stopFromDisabledIsNoop() {
        let vm = TorViewModel(
            subsystem: "test",
            backoffSchedule: [.milliseconds(10)],
            makeSession: { _ in FakeTorSession() }
        )
        vm.stop()
        #expect(vm.displayState == .disabled)
    }

    // MARK: - performStart sentinel (Finding A)

    @Test("performStart sentinel no-ops when displayState == .stopping")
    func performStartSentinelSuppresses() async throws {
        let factory = SessionFactory([FakeTorSession(), FakeTorSession()])
        let vm = TorViewModel(
            subsystem: "test",
            backoffSchedule: [.milliseconds(10)],
            makeSession: factory.make()
        )

        #expect(factory.callCount == 0)

        vm._testPerformStartSuppressedDuringStop()

        // Before fix: performStart stomps state → .starting, callCount == 1.
        // After fix: sentinel bails → .stopping preserved, callCount unchanged.
        #expect(vm.displayState == .stopping)
        #expect(factory.callCount == 0)
    }

    /// End-to-end guardrail (Finding A): tapping OFF while a backoff retry is
    /// scheduled must land in `.disabled` without respawning. With a `TestClock`
    /// the scheduled retry sleeps on virtual time we never advance, so it cannot
    /// fire — "no respawn" is a structural guarantee here, not a timing window.
    /// The deterministic proof of the underlying race lives in
    /// `performStartSentinelSuppresses`.
    @Test("stop() during a pending retry lands in .disabled with no respawn")
    func stopDuringPendingRetryDoesNotFire() async throws {
        let factory = SessionFactory([
            FakeTorSession(mode: .startThrows),
            FakeTorSession()
        ])
        let vm = TorViewModel(
            subsystem: "test",
            backoffSchedule: [.milliseconds(40)],
            clock: TestClock(),
            makeSession: factory.make()
        )

        vm.start()
        await vm.awaitSettled()
        #expect(vm.displayState == .failed)
        #expect(vm.nextRetryAt != nil)
        #expect(factory.callCount == 1)

        vm.stop()                       // cancels the pending retry
        await vm.awaitStopped()

        #expect(vm.displayState == .disabled)
        #expect(factory.callCount == 1) // retry was parked on a clock we never advanced → no respawn
    }

    // MARK: - Session cleanup (§2 / #10)

    @Test("Failed start stops the session before .failed transition")
    func failedStartCleansUpSession() async throws {
        let throwingSession = FakeTorSession(mode: .startThrows)
        let factory = SessionFactory([throwingSession, FakeTorSession()])
        let vm = TorViewModel(
            subsystem: "test",
            backoffSchedule: [.milliseconds(10)],
            clock: TestClock(),   // retry parked on virtual time; this test only inspects attempt 1
            makeSession: factory.make()
        )

        vm.start()
        await vm.awaitSettled()
        #expect(vm.displayState == .failed)
        #expect(await throwingSession.stopCalled == true)
    }

    // MARK: - Session UUID (§4)

    @Test("sessionID is fresh per start and nil when disabled")
    func sessionIDLifecycle() async throws {
        let fake = FakeTorSession()
        let vm = TorViewModel(
            subsystem: "test",
            backoffSchedule: [.milliseconds(10)],
            makeSession: { _ in fake }
        )

        #expect(vm.sessionID == nil)

        vm.start()
        let id1 = vm.sessionID          // performStart assigns sessionID synchronously
        #expect(id1 != nil)

        vm.stop()
        await vm.awaitStopped()
        #expect(vm.sessionID == nil)
    }

    @Test("sessionID changes on every performStart")
    func sessionIDIsUniquePerStart() async throws {
        let factory = SessionFactory([FakeTorSession(), FakeTorSession()])
        let vm = TorViewModel(
            subsystem: "test",
            backoffSchedule: [.milliseconds(10)],
            makeSession: factory.make()
        )

        vm.start()
        let id1 = vm.sessionID

        vm.stop()
        await vm.awaitStopped()
        vm.start()
        let id2 = vm.sessionID

        #expect(id1 != nil)
        #expect(id2 != nil)
        #expect(id1 != id2)
    }

    // MARK: - Auto-retry with backoff (§2 / new)

    @Test("Auto-retry schedules retries using the injected backoff")
    func autoRetryUsesInjectedSchedule() async throws {
        // Schedule of N delays → N retries after the initial attempt,
        // so total attempts = N + 1 before give-up.
        let schedule: [Duration] = [.milliseconds(30), .milliseconds(60), .milliseconds(90)]
        let clock = TestClock()
        let factory = SessionFactory(
            (0...schedule.count).map { _ in FakeTorSession(mode: .startThrows) }
        )
        let vm = TorViewModel(
            subsystem: "test",
            backoffSchedule: schedule,
            clock: clock,
            makeSession: factory.make()
        )

        vm.start()
        await vm.awaitSettled()                          // initial attempt fails
        #expect(vm.displayState == .failed)
        #expect(vm.failureCount == 1)
        #expect(vm.nextRetryAt != nil)

        // Fire each scheduled retry by advancing virtual time — no real delay,
        // and awaitSettled() waits for the spawned attempt to fully resolve.
        for delay in schedule {
            await clock.advance(by: delay)
            await vm.awaitSettled()
        }

        #expect(vm.failureCount == schedule.count + 1)   // initial + N retries
        #expect(vm.nextRetryAt == nil)                   // schedule exhausted
        #expect(vm.displayState == .failed)
        #expect(factory.callCount == schedule.count + 1) // one session per attempt
    }

    @Test("retry() resets counter and performs a fresh start")
    func manualRetryResetsCounter() async throws {
        // Schedule of 3 delays → initial + 3 retries = 4 total throwing attempts,
        // then give up. The 5th (working) fake is used when the user taps Retry.
        let schedule: [Duration] = [.milliseconds(10), .milliseconds(20), .milliseconds(30)]
        let clock = TestClock()
        let workingFake = FakeTorSession()
        let factory = SessionFactory([
            FakeTorSession(mode: .startThrows),      // attempt 1 (initial)
            FakeTorSession(mode: .startThrows),      // attempt 2 (retry 1)
            FakeTorSession(mode: .startThrows),      // attempt 3 (retry 2)
            FakeTorSession(mode: .startThrows),      // attempt 4 (retry 3) → give up
            workingFake                              // manual retry: fresh working session
        ])
        let vm = TorViewModel(
            subsystem: "test",
            backoffSchedule: schedule,
            clock: clock,
            makeSession: factory.make()
        )

        vm.start()
        await vm.awaitSettled()             // attempt 1 fails
        for delay in schedule {             // drive retries 2…4 to exhaustion
            await clock.advance(by: delay)
            await vm.awaitSettled()
        }
        #expect(vm.displayState == .failed)
        #expect(vm.failureCount == 4)
        #expect(vm.nextRetryAt == nil)

        vm.retry()                          // resets counter, starts fresh (synchronously .starting)
        #expect(vm.failureCount == 0)
        #expect(vm.displayState == .starting)

        await workingFake.releaseBootstrap()
        await vm.awaitSettled()
        #expect(vm.displayState == .running)
        #expect(vm.failureCount == 0)
    }

    @Test("Successful bootstrap resets failureCount to 0")
    func successResetsFailureCount() async throws {
        // First attempt throws, second attempt succeeds via the backoff retry.
        let schedule: [Duration] = [.milliseconds(20), .milliseconds(30)]
        let clock = TestClock()
        let workingFake = FakeTorSession()
        let factory = SessionFactory([
            FakeTorSession(mode: .startThrows),
            workingFake
        ])
        let vm = TorViewModel(
            subsystem: "test",
            backoffSchedule: schedule,
            clock: clock,
            makeSession: factory.make()
        )

        vm.start()
        await vm.awaitSettled()                 // first attempt fails
        #expect(vm.failureCount == 1)

        await clock.advance(by: schedule[0])    // fire the retry → working session, awaits bootstrap
        await workingFake.releaseBootstrap()
        await vm.awaitSettled()
        #expect(vm.displayState == .running)
        #expect(vm.failureCount == 0)
    }

    @Test("stop() from .failed clears retryTask and resets counter")
    func stopFromFailedCleansUp() async throws {
        let vm = TorViewModel(
            subsystem: "test",
            backoffSchedule: [.milliseconds(30)],
            clock: TestClock(),   // retry parked on virtual time; stop() must cancel it
            makeSession: { _ in FakeTorSession(mode: .startThrows) }
        )

        vm.start()
        await vm.awaitSettled()
        #expect(vm.displayState == .failed)
        #expect(vm.nextRetryAt != nil)

        vm.stop()
        await vm.awaitStopped()
        #expect(vm.displayState == .disabled)
        #expect(vm.failureCount == 0)
        #expect(vm.nextRetryAt == nil)
    }

    @Test("start() during pending retry is a no-op (lets retry fire)")
    func startDuringPendingRetryIsNoop() async throws {
        let factory = SessionFactory([
            FakeTorSession(mode: .startThrows),
            FakeTorSession(mode: .startThrows),
            FakeTorSession(mode: .startThrows)
        ])
        let vm = TorViewModel(
            subsystem: "test",
            backoffSchedule: [.milliseconds(30)],
            clock: TestClock(),
            makeSession: factory.make()
        )

        vm.start()
        await vm.awaitSettled()
        #expect(vm.displayState == .failed)
        #expect(vm.nextRetryAt != nil)
        let countBefore = factory.callCount

        vm.start()      // ignored — a retry is already scheduled
        vm.start()
        #expect(factory.callCount == countBefore)
        #expect(vm.failureCount == 1)
    }
}
