//
//  WithHardTimeout.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import Synchronization

/// The clock ran out before the call finished.
///
/// Carries the budget that elapsed so a caller declining a run can say how long
/// it waited, matching `WaitForTimeoutError` on the test side.
struct HardTimeoutError: Error, Equatable {
    let timeout: Duration
}

/// Calls `operation` and stops waiting for it after `timeout`, whether or not
/// the call can actually be cancelled.
///
/// This exists because the calls it will bound — questions to the node, which
/// `AutoTransport` routes through the in-process `DirectTransport` bridge — run
/// to completion and ignore cancellation. The textbook timeout (race work
/// against `Task.sleep` in a `withThrowingTaskGroup`) cannot help there: a task
/// group waits for *all* its children at scope exit, cancelled or not, so the
/// "timeout" would still park the caller until the call returned. The same is
/// true of the cooperative shape the standard library is converging on
/// (SE-0526 `withDeadline`, which documents "may run longer… if the operation
/// doesn't respond to cancellation immediately"). Those are the right choice
/// for cancellable I/O; this helper is for the calls that are not.
///
/// What it does instead: `operation` runs in a detached task — detached so a
/// blocking in-process call never inherits the caller's actor (a MainActor call
/// site must not end up running daemon RPCs on the main actor). The deadline is
/// fixed up front; the work task stamps the instant `operation()` returned and
/// only publishes an answer that landed before it. So once the deadline passes
/// the caller always hears `HardTimeoutError` — never a result, and never a
/// `CancellationError` that was really the call answering the courtesy cancel,
/// merely because it reached the lock while the timer task was still being
/// scheduled. When the clock wins, the work task is still sent `cancel()` — a
/// real signal for the one transport that observes it (`HTTPTransport` is
/// `URLSession`, which does cancel) — then the caller is released while the
/// call finishes in the background and its result is dropped.
///
/// Consequences, stated plainly:
///
/// - **The bound is real.** The caller returns at `timeout` no matter what the
///   call is doing.
/// - **Late answers are timeouts.** A call finishing at or after the deadline
///   reports `HardTimeoutError` even when its result reaches the lock first.
/// - **Work can outlive its caller.** An abandoned call keeps running until it
///   finishes on its own. Bounded in practice — a run asks a fixed handful of
///   questions, so the most that can be left in flight is the question count.
/// - **Cancelling the caller still works.** Cancellation reaches the work task
///   and releases the wait, rather than leaking the suspended continuation.
///
/// `clock` is injectable so tests drive the timeout with a `TestClock` instead
/// of spending real seconds — the same reason `TorViewModel(clock:)` takes one.
/// The clock bounds only the wait; it does not speed up or slow the call. The
/// parameter is generic rather than `any Clock<Duration>` so the work task can
/// compare its finish instant against the deadline — on the existential,
/// `clock.now` erases to a non-`Comparable` `any InstantProtocol`. Callers
/// holding an `any Clock<Duration>` still compile (Swift opens the existential);
/// callers that pass no clock get `ContinuousClock()`.
///
/// Nothing calls this yet — the unattended run that asks the bounded questions
/// is a later change (plan §3.4, delivery slice 8). It lands here, in the
/// shared sources, because `KernelApp`'s questions to its kernel are the same
/// uncancellable in-process shape and can use it when that need arises.
func withHardTimeout<T: Sendable, C: Clock<Duration>>(
    _ timeout: Duration,
    clock: C,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let deadline = clock.now.advanced(by: timeout)
    let race = Mutex(HardTimeoutRace<T>())

    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            let work = Task.detached {
                let finishedAt: C.Instant
                let outcome: Result<T, any Error>
                do {
                    let value = try await operation()
                    finishedAt = clock.now
                    outcome = .success(value)
                } catch {
                    finishedAt = clock.now
                    outcome = .failure(error)
                }
                race.withLock { race in
                    // An answer stamped at or past the deadline was late even
                    // if the timer task has not been scheduled yet — leave the
                    // outcome for its HardTimeoutError.
                    guard race.outcome == nil, finishedAt < deadline else { return }
                    race.outcome = outcome
                    race.timer?.cancel()
                    race.continuation?.resume(with: outcome)
                }
            }
            let timer = Task.detached {
                do {
                    try await clock.sleep(until: deadline, tolerance: nil)
                } catch {
                    // The sleep was cancelled — the call or caller-cancellation
                    // already won, or is about to. Nothing left to decide.
                    return
                }
                race.withLock { race in
                    guard race.outcome == nil else { return }
                    let outcome = Result<T, any Error>.failure(
                        HardTimeoutError(timeout: timeout))
                    race.outcome = outcome
                    race.work?.cancel()
                    race.continuation?.resume(with: outcome)
                }
            }
            race.withLock { race in
                race.continuation = continuation
                race.work = work
                race.timer = timer
                if let outcome = race.outcome {
                    // An event won before anything was stored: its resume found
                    // no continuation and was dropped, so resume now — and send
                    // the cancel it could not send to tasks that did not exist
                    // in the state yet.
                    work.cancel()
                    timer.cancel()
                    continuation.resume(with: outcome)
                }
            }
        }
    } onCancel: {
        race.withLock { race in
            guard race.outcome == nil else { return }
            let outcome = Result<T, any Error>.failure(CancellationError())
            race.outcome = outcome
            race.work?.cancel()
            race.timer?.cancel()
            race.continuation?.resume(with: outcome)
        }
    }
}

/// `withHardTimeout(_:operation:)` on the wall clock. Generic clock parameters
/// cannot carry a default value, so the convenience overload supplies it.
func withHardTimeout<T: Sendable>(
    _ timeout: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withHardTimeout(timeout, clock: ContinuousClock(), operation: operation)
}

/// The shared state inside `withHardTimeout`. `outcome` is written exactly once
/// — by whichever of the call, the clock, or caller-cancellation finishes first
/// — and the continuation is resumed exactly once: either by that winner if the
/// continuation is already installed, or by the setup lock in the caller if an
/// outcome beat it there. Those two orderings are mutually exclusive, so the
/// resume can never happen twice.
///
/// File-scope rather than nested because Swift does not allow a type nested in
/// a generic function.
private struct HardTimeoutRace<T> {
    var outcome: Result<T, any Error>?
    var continuation: CheckedContinuation<T, any Error>?
    var work: Task<Void, Never>?
    var timer: Task<Void, Never>?
}
