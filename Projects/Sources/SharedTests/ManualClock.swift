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
        var sleepers: [
            (id: Int, deadline: Instant,
             continuation: CheckedContinuation<Void, any Error>)
        ] = []
        var armedWaiters: [
            (id: Int,
             continuation: CheckedContinuation<Instant, any Error>)
        ] = []
    }
    private let state = Mutex(State())

    var now: Instant { state.withLock { $0.now } }
    var minimumResolution: Duration { .zero }

    /// How many sleepers are parked waiting on `now` — test surface for
    /// "registration happened", so a cancellation case can act *after* the
    /// sleeper lands rather than racing it.
    var parkedSleepers: Int { state.withLock { $0.sleepers.count } }

    /// How many `waitForNextDeadline` callers are parked waiting on a
    /// sleeper to register — the same registration-happened surface as
    /// `parkedSleepers`, for the waiter's side of the handshake.
    var armedWaiterCount: Int { state.withLock { $0.armedWaiters.count } }

    /// The earliest deadline among parked sleepers, or nil — a
    /// non-suspending sample. For "wake me when one parks", use
    /// `waitForNextDeadline()`.
    var earliestParkedDeadline: Instant? {
        state.withLock {
            $0.sleepers.min { $0.deadline < $1.deadline }?.deadline
        }
    }

    /// Suspends until a sleeper parks and returns the earliest parked
    /// deadline AT THE MOMENT OF THE PARK — a wake signal, not a promise:
    /// a nearer sleeper can register before the caller is scheduled, so a
    /// driver re-samples `earliestParkedDeadline` before advancing rather
    /// than trusting the delivered value. Returns at once when a sleeper
    /// is already parked, so a park can't be missed between a sample and
    /// the wait. Throws `CancellationError` if the caller is cancelled
    /// first — the same contract `sleep` and `Gate.wait` keep, so a
    /// suite's `.timeLimit` still reaps a wedged driver.
    func waitForNextDeadline() async throws -> Instant {
        try Task.checkCancellation()
        let id = state.withLock { s -> Int in
            defer { s.nextID += 1 }
            return s.nextID
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Instant, any Error>) in
                enum Action {
                    case deliver(Instant), throwCancel, park
                }
                // Same under-lock three-way as `sleep`: a cancel racing
                // registration either finds the entry (`onCancel`) or is
                // answered here — and a sleeper already parked is
                // delivered without suspending.
                switch state.withLock({ s -> Action in
                    if Task.isCancelled { return .throwCancel }
                    if let earliest = s.sleepers.min(by: {
                        $0.deadline < $1.deadline
                    }) {
                        return .deliver(earliest.deadline)
                    }
                    s.armedWaiters.append((id, continuation))
                    return .park
                }) {
                case .deliver(let deadline):
                    continuation.resume(returning: deadline)
                case .throwCancel:
                    continuation.resume(throwing: CancellationError())
                case .park: break
                }
            }
        } onCancel: {
            state.withLock { s -> CheckedContinuation<Instant, any Error>? in
                guard let index = s.armedWaiters.firstIndex(where: {
                    $0.id == id
                }) else { return nil }
                return s.armedWaiters.remove(at: index).continuation
            }?.resume(throwing: CancellationError())
        }
    }

    func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        try Task.checkCancellation()
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
                        park([(CheckedContinuation<Instant, any Error>, Instant)])
                }
                switch state.withLock({ s -> Action in
                    if Task.isCancelled { return .throwCancel }
                    if deadline <= s.now { return .resume }
                    s.sleepers.append((id, deadline, continuation))
                    // A park is the armed event `waitForNextDeadline`
                    // callers suspended on — released atomically with the
                    // append, resumed outside the lock, each handed the
                    // earliest parked deadline at this instant. `min` is
                    // force-unwrapped under the invariant the entry just
                    // appended guarantees: the queue cannot be empty here.
                    let earliest = s.sleepers.min {
                        $0.deadline < $1.deadline
                    }!.deadline
                    let waiters = s.armedWaiters
                    s.armedWaiters.removeAll()
                    return .park(
                        waiters.map { ($0.continuation, earliest) })
                }) {
                case .resume: continuation.resume()
                case .throwCancel:
                    continuation.resume(throwing: CancellationError())
                case .park(let armed):
                    for (waiter, deadline) in armed {
                        waiter.resume(returning: deadline)
                    }
                }
            }
        } onCancel: {
            state.withLock { s -> CheckedContinuation<Void, any Error>? in
                guard let index = s.sleepers.firstIndex(where: {
                    $0.id == id
                }) else { return nil }
                return s.sleepers.remove(at: index).continuation
            }?.resume(throwing: CancellationError())
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
        let due = state.withLock {
            s -> [CheckedContinuation<Void, any Error>] in
            let instant = makeInstant(&s)
            if instant > s.now { s.now = instant }
            let due = s.sleepers.filter { $0.deadline <= s.now }
                .sorted { $0.deadline < $1.deadline }
            s.sleepers.removeAll { $0.deadline <= s.now }
            return due.map(\.continuation)
        }
        for continuation in due { continuation.resume() }
    }
}

extension ManualClock {
    /// Advances the clock toward the earliest armed deadline — never more
    /// than `step` per hop — until `done` opens: the run's own
    /// completion, not a turn count, is the bound. A deadline inside the
    /// hop lands at its own instant, so naps wake in real-time order; one
    /// beyond it is approached hop-wise instead of fired outright,
    /// because an armed hard-timeout bound is not a safely schedulable
    /// event — it guards detached work that still needs real executor
    /// turns, and jumping to its deadline would stamp the work's answer
    /// late no matter when the bound's own timer task runs. Each hop's
    /// yield is a real turn for that work, so a bound only fires after it
    /// has spent a `step`-proportional budget of turns waiting on the
    /// work; starvation past that budget still flips the verdict
    /// honestly, it just can't be caused by the drive. When nothing is
    /// parked the run is mid-hop: the drive suspends on the next armed
    /// deadline racing `done`, never polling — the only real-time element
    /// left is a suite's `.timeLimit`, which reaps a wedged drive by
    /// cancelling that wait.
    func drive(untilDone done: Gate, by step: Duration) async throws {
        precondition(step > .zero, "drive needs a positive step")
        while !done.isOpen {
            try Task.checkCancellation()
            if let deadline = earliestParkedDeadline {
                advance(to: min(deadline, now.advanced(by: step)))
                await Task.yield()
            } else {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { _ = try await self.waitForNextDeadline() }
                    group.addTask { try await done.wait() }
                    try await group.next()
                    group.cancelAll()
                }
            }
        }
    }
}
