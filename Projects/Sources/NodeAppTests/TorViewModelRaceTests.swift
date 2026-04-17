//
//  TorViewModelRaceTests.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2026 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import Testing
import Tor
@testable import NodeApp

// MARK: - waitFor

/// Thrown by `waitFor` when the timeout elapses. Propagates via `try await`
/// so the test body stops executing instead of continuing with stale state.
fileprivate struct WaitForTimeoutError: Error {
    let timeout: Duration
}

/// Polls `predicate` until it returns true or `timeout` elapses.
///
/// Used instead of magic `Task.sleep(for:)` values when a test asserts on
/// state that becomes true asynchronously. Swift Testing's `confirmation`
/// is the wrong tool here — it expects a discrete event callback to fire.
/// Our tests assert on `@Observable` state convergence (e.g.
/// `vm.displayState == .disabled`), for which there is no native
/// Swift Testing primitive as of this writing.
///
/// Fails the test (via `Issue.record`) and throws `WaitForTimeoutError`
/// on timeout — both to mark the failure and to halt the awaiting body so
/// downstream assertions don't cascade and obscure the real issue.
///
/// - Parameters:
///   - timeout: Maximum time to wait before failing.
///   - pollEvery: Interval between predicate evaluations (default 10ms).
///   - predicate: Main-actor-isolated snapshot check. Must be cheap.
@MainActor
fileprivate func waitFor(
    timeout: Duration,
    pollEvery: Duration = .milliseconds(10),
    _ predicate: @MainActor () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !predicate() {
        if ContinuousClock.now > deadline {
            Issue.record(
                "waitFor timed out after \(timeout)",
                sourceLocation: sourceLocation
            )
            throw WaitForTimeoutError(timeout: timeout)
        }
        try await Task.sleep(for: pollEvery)
    }
}

// MARK: - FakeTorSession

/// Test double for `TorSession` that blocks bootstrap until released.
///
/// Used to deterministically reach the race windows where `TorViewModel.stop()`
/// must cancel an in-flight `start()` Task before it can write state, and
/// where the auto-retry state machine must schedule/cancel retries under
/// rapid user input.
actor FakeTorSession: TorSession {

    enum Mode: Sendable {
        case blockUntilReleased
        case startThrows
    }

    private let mode: Mode
    private var bootstrapGate: CheckedContinuation<Void, Error>?
    private var bootstrapPreReleased = false
    private var eventContinuation: AsyncStream<TorEvent>.Continuation?

    private(set) var startCalled = false
    private(set) var stopCalled = false
    private(set) var bootstrapWasCancelled = false

    init(mode: Mode = .blockUntilReleased) {
        self.mode = mode
    }

    // MARK: TorSession

    var events: AsyncStream<TorEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
        }
    }

    var socksEndpoint: HostPort? {
        HostPort(host: "127.0.0.1", port: 9050)
    }

    func start() async throws {
        startCalled = true
        if case .startThrows = mode {
            struct FakeStartError: Error {}
            throw FakeStartError()
        }
    }

    func waitUntilBootstrapped(timeout: Duration) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                Task { await self.storeGate(cont) }
            }
        } onCancel: {
            Task { await self.cancelBootstrap() }
        }
    }

    func stop() async {
        stopCalled = true
        if let gate = bootstrapGate {
            gate.resume(throwing: CancellationError())
            bootstrapGate = nil
        }
        eventContinuation?.finish()
        eventContinuation = nil
    }

    // MARK: Test hooks

    private func storeGate(_ cont: CheckedContinuation<Void, Error>) {
        // Cancel-before-store race: if cancelBootstrap fired before this
        // task reached the actor, resume immediately with CancellationError
        // instead of leaking the continuation (Finding B round-2 review).
        if bootstrapWasCancelled {
            cont.resume(throwing: CancellationError())
            return
        }
        // Symmetric race for successful release: a test that calls
        // `releaseBootstrap()` right after observing `.starting` may beat
        // the async storeGate task to the actor. Honor the pre-release flag.
        if bootstrapPreReleased {
            cont.resume(returning: ())
            return
        }
        self.bootstrapGate = cont
    }

    private func cancelBootstrap() {
        bootstrapWasCancelled = true
        if let gate = bootstrapGate {
            gate.resume(throwing: CancellationError())
            bootstrapGate = nil
        }
    }

    /// Releases the bootstrap gate so `waitUntilBootstrapped()` returns normally.
    ///
    /// If called before `storeGate` has landed on the actor, sets a
    /// pre-release flag so the continuation is resumed immediately when it
    /// eventually stores. Mirrors the `bootstrapWasCancelled` contract.
    func releaseBootstrap() {
        if let gate = bootstrapGate {
            gate.resume(returning: ())
            bootstrapGate = nil
        } else {
            bootstrapPreReleased = true
        }
    }
}

// MARK: - SessionFactory helper

/// Main-actor–safe factory that hands out a pre-staged sequence of fakes.
///
/// `TorViewModel` invokes the factory from `@MainActor`, so the internal
/// mutation is trivially safe — we just need a type that is `Sendable`
/// for the closure's `@Sendable` requirement.
@MainActor
final class SessionFactory {
    private var queue: [any TorSession]
    private(set) var callCount = 0

    init(_ sessions: [any TorSession]) {
        self.queue = sessions
    }

    nonisolated func make() -> @Sendable (TorConfiguration) -> any TorSession {
        { @Sendable [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return FakeTorSession() }
                self.callCount += 1
                return self.queue.isEmpty ? FakeTorSession() : self.queue.removeFirst()
            }
        }
    }
}

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
        try await waitFor(timeout: .milliseconds(500)) { vm.displayState == .starting }

        vm.stop()
        try await waitFor(timeout: .seconds(1)) { vm.displayState == .disabled }

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
        try await waitFor(timeout: .milliseconds(500)) { vm.displayState == .starting }

        vm.stop()
        await fake.releaseBootstrap()
        try await waitFor(timeout: .seconds(1)) { vm.displayState == .disabled }

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
        try await Task.sleep(for: .milliseconds(50))
        vm.stop()
        vm.stop()
        try await Task.sleep(for: .milliseconds(200))

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
        try await waitFor(timeout: .milliseconds(500)) { vm.displayState == .starting }
        vm.stop()               // enters .stopping
        vm.start()              // queued (displayState is .stopping)

        // After the stop task finishes it should call start() again,
        // which creates a SECOND session.
        try await waitFor(timeout: .seconds(2)) { factory.callCount == 2 }

        // Stability probe: catch monotonic overshoot past 2 (pathological
        // performStart re-entry). callCount is strictly increasing.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(factory.callCount == 2, "callCount must not advance past 2")
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
        try await Task.sleep(for: .milliseconds(30))
        vm.stop()               // .stopping
        vm.start()              // pending = true
        vm.stop()               // pending cleared
        try await Task.sleep(for: .milliseconds(300))

        #expect(vm.displayState == .disabled)
    }

    @Test("start() failure surfaces as .failed, not .running")
    func startFailureSetsFailed() async throws {
        let vm = TorViewModel(
            subsystem: "test",
            backoffSchedule: [.milliseconds(500)],   // long enough to observe .failed
            makeSession: { _ in FakeTorSession(mode: .startThrows) }
        )

        vm.start()
        try await Task.sleep(for: .milliseconds(150))

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
        try await Task.sleep(for: .milliseconds(30))
        #expect(vm.displayState == .starting)

        vm.start()
        #expect(vm.displayState == .starting)

        vm.stop()
        try await Task.sleep(for: .milliseconds(200))
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

    /// End-to-end guardrail (Finding A): the common path of tapping OFF
    /// while a backoff retry is scheduled must land in `.disabled` without
    /// respawning. This test does NOT claim to fail on pre-fix code — the
    /// cancel-during-sleep branch short-circuits before the `MainActor.run`
    /// hop even without the `performStart` sentinel. The deterministic
    /// proof of the race lives in `performStartSentinelSuppresses`.
    @Test("stop() during a pending retry lands in .disabled with no respawn")
    func stopDuringPendingRetryDoesNotFire() async throws {
        let factory = SessionFactory([
            FakeTorSession(mode: .startThrows),
            FakeTorSession()
        ])
        let vm = TorViewModel(
            subsystem: "test",
            backoffSchedule: [.milliseconds(40)],
            makeSession: factory.make()
        )

        vm.start()
        try await waitFor(timeout: .milliseconds(500)) {
            vm.displayState == .failed && vm.nextRetryAt != nil
        }
        #expect(factory.callCount == 1)

        vm.stop()
        try await waitFor(timeout: .milliseconds(500)) {
            vm.displayState == .disabled
        }

        // Stability probe: catch monotonic overshoot past 1 (a late-firing
        // retry spawning a second session).
        try? await Task.sleep(for: .milliseconds(100))
        #expect(vm.displayState == .disabled)
        #expect(factory.callCount == 1, "callCount must not advance past 1")
    }

    // MARK: - Session cleanup (§2 / #10)

    @Test("Failed start stops the session before .failed transition")
    func failedStartCleansUpSession() async throws {
        let throwingSession = FakeTorSession(mode: .startThrows)
        let factory = SessionFactory([throwingSession, FakeTorSession()])
        let vm = TorViewModel(
            subsystem: "test",
            backoffSchedule: [.seconds(30)],     // prevent auto-retry from firing
            makeSession: factory.make()
        )

        vm.start()
        try await Task.sleep(for: .milliseconds(150))
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
        try await Task.sleep(for: .milliseconds(30))
        let id1 = vm.sessionID
        #expect(id1 != nil)

        vm.stop()
        try await Task.sleep(for: .milliseconds(200))
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
        try await Task.sleep(for: .milliseconds(30))
        let id1 = vm.sessionID

        vm.stop()
        try await Task.sleep(for: .milliseconds(200))
        vm.start()
        try await Task.sleep(for: .milliseconds(30))
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
        let vm = TorViewModel(
            subsystem: "test",
            backoffSchedule: schedule,
            makeSession: { _ in FakeTorSession(mode: .startThrows) }
        )

        vm.start()
        try await Task.sleep(for: .milliseconds(10))
        #expect(vm.displayState == .failed)
        #expect(vm.failureCount == 1)
        #expect(vm.nextRetryAt != nil)

        // Advance through all three scheduled retries (≈ 30 + 60 + 90 ms),
        // leaving a generous margin for the 4th attempt to fire and fail.
        try await Task.sleep(for: .milliseconds(400))
        #expect(vm.failureCount == schedule.count + 1)       // initial + N retries
        #expect(vm.nextRetryAt == nil)                       // exhausted
        #expect(vm.displayState == .failed)
    }

    @Test("retry() resets counter and performs a fresh start")
    func manualRetryResetsCounter() async throws {
        // Schedule of 3 delays → initial + 3 retries = 4 total throwing attempts,
        // then give up. The 5th (working) fake is used when the user taps Retry.
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
            backoffSchedule: [.milliseconds(10), .milliseconds(20), .milliseconds(30)],
            makeSession: factory.make()
        )

        vm.start()
        try await waitFor(timeout: .seconds(2)) {
            vm.failureCount == 4 && vm.nextRetryAt == nil
        }
        #expect(vm.displayState == .failed)

        vm.retry()
        try await waitFor(timeout: .milliseconds(500)) {
            vm.failureCount == 0 && vm.displayState == .starting
        }

        await workingFake.releaseBootstrap()
        try await waitFor(timeout: .seconds(1)) { vm.displayState == .running }
        #expect(vm.failureCount == 0)
    }

    @Test("Successful bootstrap resets failureCount to 0")
    func successResetsFailureCount() async throws {
        // First attempt throws, second attempt succeeds via the backoff retry.
        let workingFake = FakeTorSession()
        let factory = SessionFactory([
            FakeTorSession(mode: .startThrows),
            workingFake
        ])
        let vm = TorViewModel(
            subsystem: "test",
            backoffSchedule: [.milliseconds(20), .milliseconds(30)],
            makeSession: factory.make()
        )

        vm.start()
        try await Task.sleep(for: .milliseconds(10))
        #expect(vm.failureCount == 1)

        // Let the auto-retry fire.
        try await Task.sleep(for: .milliseconds(50))
        #expect(vm.displayState == .starting)

        await workingFake.releaseBootstrap()
        try await Task.sleep(for: .milliseconds(150))
        #expect(vm.displayState == .running)
        #expect(vm.failureCount == 0)
    }

    @Test("stop() from .failed clears retryTask and resets counter")
    func stopFromFailedCleansUp() async throws {
        let vm = TorViewModel(
            subsystem: "test",
            backoffSchedule: [.seconds(30)],         // long so retry doesn't fire during test
            makeSession: { _ in FakeTorSession(mode: .startThrows) }
        )

        vm.start()
        try await Task.sleep(for: .milliseconds(150))
        #expect(vm.displayState == .failed)
        #expect(vm.nextRetryAt != nil)

        vm.stop()
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
            backoffSchedule: [.seconds(30)],         // long window
            makeSession: factory.make()
        )

        vm.start()
        try await Task.sleep(for: .milliseconds(150))
        #expect(vm.displayState == .failed)
        #expect(vm.nextRetryAt != nil)
        let countBefore = factory.callCount

        vm.start()      // should be ignored — retry is scheduled
        vm.start()
        #expect(factory.callCount == countBefore)
        #expect(vm.failureCount == 1)
    }
}
