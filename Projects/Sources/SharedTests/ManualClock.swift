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
/// computes its deadline from `now` at invocation.
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
    }
    private let state = Mutex(State())

    var now: Instant { state.withLock { $0.now } }
    var minimumResolution: Duration { .zero }

    /// How many sleepers are parked waiting on `now` — test surface for
    /// "registration happened", so a cancellation case can act *after* the
    /// sleeper lands rather than racing it.
    var parkedSleepers: Int { state.withLock { $0.sleepers.count } }

    func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        try Task.checkCancellation()
        let id = state.withLock { s -> Int in
            defer { s.nextID += 1 }
            return s.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                enum Action { case resume, throwCancel, park }
                // Decided under the lock so a cancel racing registration
                // either finds the entry (`onCancel`) or is answered here —
                // never both, never neither.
                switch state.withLock({ s -> Action in
                    if Task.isCancelled { return .throwCancel }
                    if deadline <= s.now { return .resume }
                    s.sleepers.append((id, deadline, continuation))
                    return .park
                }) {
                case .resume: continuation.resume()
                case .throwCancel:
                    continuation.resume(throwing: CancellationError())
                case .park: break
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
