//
//  ManualClock.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Synchronization

/// A clock with no hidden scheduling. `TestClock` makes every `sleep` call
/// and every woken sleeper pay `Task.megaYield` — twenty detached,
/// background-priority hops — so a virtual wait's real cost scales with the
/// suspensions crossed: the 241-second advance in `NodeRunTests`'s
/// `waitRunsOnInjectedClock` walks ~480 naps, ~9,600 detached hops, which
/// starved that suite's two clock tests to their minute limit on a loaded CI
/// runner (the same failure element-x-ios#6022 replaced `TestClock` over) —
/// and `WithHardTimeoutTests`'s late-answer case starved the same way when a
/// single woken sleeper's hops lost the executor for minutes. Here `advance`
/// resumes due sleepers synchronously, and a sleep at or past `now` returns
/// at once — equality is not a trap, and a late registration after the last
/// advance returns instead of parking. The one ordering a test still owes:
/// a sleep whose deadline lands *ahead* of the final advance suspends
/// forever, so gate each `advance` on the bound's request — `withHardTimeout`
/// computes its deadline from `now` at invocation. A driver that needs the
/// park itself as an event — an event-exact advance that visits every armed
/// deadline in order — awaits `waitForNextDeadline()` (or samples
/// `earliestParkedDeadline`) instead of polling `parkedSleepers`.
///
/// Every parked sleeper is also *classified*: `ownedBySubject` records
/// `ClockSubject.isCurrent` at park time, which `Task { }` children inherit
/// and `Task.detached` never does. The run's own naps mark it, the
/// `withHardTimeout` timer tasks it spawns do not — so a driver can tell a
/// nap it is allowed to fire from a bound it must hold: the bound guards
/// detached work that still needs real executor time, and firing it would
/// stamp the work's answer late however fast the drive hopped. The rule is
/// Tokio's paused clock and Go's testing/synctest: virtual time advances
/// only to sleeps the subject itself parked.
final class ManualClock: Clock, Sendable {
    /// The minimal `InstantProtocol`: a `Duration` offset from start.
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }
        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }
        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct State {
        var now = Instant(offset: .zero)
        var nextID = 0
        /// Bumped on every change a driver could act on — a park, a
        /// cancellation removal, an advance — which is what lets a
        /// `waitForChange` caller wait on "something changed since my
        /// sample" without polling and without losing a change that
        /// landed between the sample and the wait.
        var generation = 0
        var sleepers: [
            (id: Int, deadline: Instant, ownedBySubject: Bool,
             continuation: CheckedContinuation<Void, any Error>)
        ] = []
        var changeWaiters: [
            (id: Int,
             continuation: CheckedContinuation<Void, any Error>)
        ] = []
    }
    private let state = Mutex(State())

    /// Called each time a `waitForChange` caller parks, after it is
    /// registered and outside the lock. The clock's own tests use it to
    /// act once a waiter is suspended, where a yield loop could only
    /// guess. The same reporter shape `ObservedClock` gives sleeps.
    private let onWaiterArmed: (@Sendable () -> Void)?

    init(onWaiterArmed: (@Sendable () -> Void)? = nil) {
        self.onWaiterArmed = onWaiterArmed
    }

    var now: Instant { state.withLock { $0.now } }
    var minimumResolution: Duration { .zero }

    /// How many sleepers are parked waiting on `now` — test surface for
    /// "registration happened", so a cancellation case can act *after* the
    /// sleeper lands rather than racing it.
    var parkedSleepers: Int { state.withLock { $0.sleepers.count } }

    /// How many `waitForChange` callers are parked waiting on a clock
    /// event — the same registration-happened surface as
    /// `parkedSleepers`, for the waiter's side of the handshake.
    var armedWaiterCount: Int { state.withLock { $0.changeWaiters.count } }

    /// The earliest deadline among parked sleepers, or nil — a
    /// non-suspending sample. For "wake me when one parks", use
    /// `waitForNextDeadline()`.
    var earliestParkedDeadline: Instant? {
        state.withLock {
            $0.sleepers.min { $0.deadline < $1.deadline }?.deadline
        }
    }

    /// Suspends until a sleeper parks and returns the earliest parked
    /// deadline at the wake — a wake signal, not a promise: a nearer
    /// sleeper can register before the caller is scheduled, so a driver
    /// re-samples `earliestParkedDeadline` before advancing rather than
    /// trusting the delivered value. Returns at once when a sleeper is
    /// already parked, so a park can't be missed between a sample and
    /// the wait. Throws `CancellationError` if the caller is cancelled
    /// first — the same contract `sleep` and `Gate.wait` keep, so a
    /// suite's `.timeLimit` still reaps a wedged driver.
    func waitForNextDeadline() async throws -> Instant {
        while true {
            try Task.checkCancellation()
            let pending = state.withLock { s in
                (s.sleepers.min { $0.deadline < $1.deadline }?.deadline,
                 s.generation)
            }
            if let deadline = pending.0 { return deadline }
            try await waitForChange(since: pending.1)
        }
    }

    /// Returns once the sleeper list changed after `generation` — the
    /// "check, then wait" handshake that makes a missed wake impossible:
    /// a change that lands between the caller's sample and this wait is
    /// seen here as an already-stale generation and returns at once.
    /// Throws `CancellationError` if the caller is cancelled first.
    func waitForChange(since generation: Int) async throws {
        try Task.checkCancellation()
        let id = state.withLock { s -> Int in
            defer { s.nextID += 1 }
            return s.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                // Same under-lock three-way as `sleep`: a cancel racing
                // registration either finds the entry (`onCancel`) or is
                // answered here — and a generation already stale is
                // answered without suspending.
                enum Action {
                    case resume, throwCancel, park
                }
                switch state.withLock({ s -> Action in
                    if Task.isCancelled { return .throwCancel }
                    if s.generation != generation { return .resume }
                    s.changeWaiters.append((id, continuation))
                    return .park
                }) {
                case .resume: continuation.resume()
                case .throwCancel:
                    continuation.resume(throwing: CancellationError())
                case .park: onWaiterArmed?()
                }
            }
        } onCancel: {
            state.withLock { s -> CheckedContinuation<Void, any Error>? in
                guard let index = s.changeWaiters.firstIndex(where: {
                    $0.id == id
                }) else { return nil }
                return s.changeWaiters.remove(at: index).continuation
            }?.resume(throwing: CancellationError())
        }
    }

    func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        try Task.checkCancellation()
        // Read on the *sleeping* task: `Task { }` children inherit the
        // mark where `Task.detached` never does — the run's naps carry
        // it, its bound timers cannot.
        let ownedBySubject = ClockSubject.isCurrent
        let id = state.withLock { s -> Int in
            defer { s.nextID += 1 }
            return s.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                // Decided under the lock so a cancel racing registration
                // either finds the entry (`onCancel`) or is answered here —
                // never both, never neither.
                enum Action {
                    case resume, throwCancel,
                        park([CheckedContinuation<Void, any Error>])
                }
                switch state.withLock({ s -> Action in
                    if Task.isCancelled { return .throwCancel }
                    if deadline <= s.now { return .resume }
                    s.sleepers.append(
                        (id, deadline, ownedBySubject, continuation))
                    // A park is a change every waiter suspended on —
                    // released atomically with the append, resumed
                    // outside the lock.
                    s.generation += 1
                    defer { s.changeWaiters.removeAll() }
                    return .park(s.changeWaiters.map(\.continuation))
                }) {
                case .resume: continuation.resume()
                case .throwCancel:
                    continuation.resume(throwing: CancellationError())
                case .park(let waiters):
                    for waiter in waiters { waiter.resume() }
                }
            }
        } onCancel: {
            let removed = state.withLock {
                s -> (continuation: CheckedContinuation<Void, any Error>?,
                      woken: [CheckedContinuation<Void, any Error>]) in
                guard let index = s.sleepers.firstIndex(where: {
                    $0.id == id
                }) else { return (nil, []) }
                let removed = s.sleepers.remove(at: index).continuation
                // A removal is a change too — a driver holding on this
                // sleeper must re-sample rather than hold forever.
                s.generation += 1
                defer { s.changeWaiters.removeAll() }
                return (removed, s.changeWaiters.map(\.continuation))
            }
            for waiter in removed.woken { waiter.resume() }
            removed.continuation?.resume(throwing: CancellationError())
        }
    }

    /// Moves `now` forward — never back — and resumes every sleeper due by
    /// the new instant, synchronously: no yields, so the number of real task
    /// hops an advance costs does not depend on the runner's load.
    func advance(to instant: Instant) {
        advance { _ in instant }
    }

    /// Advances `now` by `duration` — computed and applied under the one
    /// lock, so two concurrent relative advances cannot read the same base
    /// and silently drop one.
    func advance(by duration: Duration) {
        advance { s in s.now.advanced(by: duration) }
    }

    /// Applies an instant under the lock, then issues every due
    /// `continuation.resume()` outside it — in deadline order, which only
    /// orders the resume CALLS. Resumption enqueues the task; the observable
    /// run order is the executor's, so a test that needs "the earlier timer
    /// fired first" still pins that order with a `Gate`.
    private func advance(_ makeInstant: (inout State) -> Instant) {
        let resumed = state.withLock {
            s -> (due: [CheckedContinuation<Void, any Error>],
                  woken: [CheckedContinuation<Void, any Error>]) in
            let instant = makeInstant(&s)
            if instant > s.now { s.now = instant }
            let due = s.sleepers.filter { $0.deadline <= s.now }
                .sorted { $0.deadline < $1.deadline }
            s.sleepers.removeAll { $0.deadline <= s.now }
            s.generation += 1
            defer { s.changeWaiters.removeAll() }
            return (due.map(\.continuation), s.changeWaiters.map(\.continuation))
        }
        for continuation in resumed.due { continuation.resume() }
        for waiter in resumed.woken { waiter.resume() }
    }
}

extension ManualClock {
    /// What a driver may do with the parked sleepers right now.
    enum Step {
        /// A bound is parked — time is owed to detached work, so hold.
        case hold
        /// Fire the earliest parked nap the subject itself owns.
        case advance(Instant)
    }

    /// The driver's next move plus the generation it was decided at —
    /// sampled under the one lock, so the pair is atomic. `hold` while
    /// any bound is parked (time is owed to work, not the clock), else
    /// `advance` to the earliest nap the subject owns, else `nil` when
    /// nothing is parked. A driver that decided there is nothing to do
    /// waits on `waitForChange(since:)` with *this* generation — a change
    /// landing between the sample and the wait is then never missed.
    var nextStep: (step: Step?, generation: Int) {
        state.withLock { s in
            if s.sleepers.contains(where: { !$0.ownedBySubject }) {
                return (.hold, s.generation)
            }
            let nap = s.sleepers.min { $0.deadline < $1.deadline }
            return (nap.map { .advance($0.deadline) }, s.generation)
        }
    }

    /// Suspends until a bound is parked, then fires the earliest one —
    /// the test's way to run a parked question's clock out explicitly.
    /// The suspend is the trap a fake sets: it can signal "I will never
    /// answer" before the bound's timer task has even run, so a one-shot
    /// sample could find no bound and return having fired nothing.
    func expireEarliestBound() async throws {
        while true {
            try Task.checkCancellation()
            let pending = state.withLock { s in
                (s.sleepers.filter { !$0.ownedBySubject }
                    .min { $0.deadline < $1.deadline }?.deadline,
                 s.generation)
            }
            if let deadline = pending.0 {
                advance(to: deadline)
                return
            }
            try await waitForChange(since: pending.1)
        }
    }

    /// Advances the clock until `done` opens: the run's own completion,
    /// not a turn count, is the bound. The drive is event-driven — it
    /// suspends on clock events and never sleeps on the real clock. It
    /// advances only to a nap the subject itself parked: a parked bound
    /// freezes time until its answer cancels it (or a test fires it with
    /// `expireEarliestBound`), because the bound guards detached work that
    /// still needs real executor turns — firing it would stamp the work's
    /// answer late however the drive was stepped, which is exactly the
    /// starvation the stepped drive could never rule out.
    ///
    /// The run under test must be marked `ClockSubject.isCurrent` around
    /// its `Task { }`, or every sleeper reads as a bound and the drive
    /// holds forever. `done` must end on every verdict — a gate only one
    /// verdict produces turns an honest flip into a `.timeLimit` hang.
    /// The run's own completion gate opens in its `defer`; a checkpoint
    /// gate driven toward is abandoned there instead, and the drive then
    /// throws `Gate.Abandoned` naming the caller's line (the rule is
    /// stated once, on `Gate`). When nothing is parked the run is
    /// mid-hop: the drive waits on the next clock change racing `done`,
    /// never polling.
    func drive(
        untilDone done: Gate, fileID: String = #fileID, line: Int = #line
    ) async throws {
        while !done.isOpen {
            try Task.checkCancellation()
            let (step, generation) = nextStep
            if case .advance(let deadline)? = step {
                advance(to: deadline)
                continue
            }
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await self.waitForChange(since: generation) }
                group.addTask { try await done.wait(fileID: fileID, line: line) }
                try await group.next()
                group.cancelAll()
            }
        }
    }
}

/// The task-local that marks the task under test so a `ManualClock` can
/// tell the run's own naps from the bound timers `withHardTimeout`
/// parks in `Task.detached`: `Task { }` inherits task-locals where
/// `Task.detached` never does, so every sleeper the run itself parks
/// records `isCurrent == true` and every bound's reads `false`. Not
/// `Test.current` — Apple only documents that as "may be nil" in a
/// detached task, which is the wrong foundation for a classifier.
///
/// Every test that drives wraps its run task:
///
///     let run = ClockSubject.$isCurrent.withValue(true) {
///         Task { @MainActor in
///             defer { done.open() }
///             return await NodeRun.perform(/* ... */)
///         }
///     }
enum ClockSubject {
    /// True on the task under test and its `Task { }` children; false
    /// inside `Task.detached` — `withHardTimeout`'s work and timer.
    @TaskLocal static var isCurrent = false
}
