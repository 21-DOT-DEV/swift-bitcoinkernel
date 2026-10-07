//
//  Gate.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import Synchronization

/// A one-shot event a test *awaits* instead of sampling: `wait()` returns
/// once `open()` has been called, in either order.
///
/// This is the way out of the two shapes flaky concurrency tests take —
/// acting before the system under test has reached the state the action
/// assumes ("yield ten times, then poke"), and checking a flag some other
/// task was meant to set by now ("yield ten times, then `#expect(flag)`").
/// Both are bets on executor scheduling that lose on a loaded CI runner.
/// A gate makes the step event-ordered instead: the test suspends until the
/// event itself happens — no real-time budget, no poll window, no magic
/// yield count.
///
/// `wait()` throws `CancellationError` if the *caller* is cancelled, so a
/// suite's `.timeLimit` turns a stuck wait — which can only mean the
/// contract under test was broken — into a named timeout failure instead
/// of a hung job. For the opposite contract, `waitIgnoringCancellation()`
/// parks through cancellation entirely: the closest a test can get to
/// work that cannot be cancelled.
///
/// Prefer this over `waitFor`, which samples a predicate on the real clock
/// and therefore always keeps a nonzero race window. `waitFor` stays the
/// escape hatch for waits no event can describe — a filesystem side
/// effect, a third-party callback with no hook.
///
/// Foundation-only — compiled into both app test bundles via the
/// `Sources/SharedTests/**` glob, and needs no `NODEAPP_TESTS`/
/// `KERNELAPP_TESTS` discriminator because it does not import either app.
final class Gate: Sendable {

    private struct State {
        var open = false
        var waiters: [UUID: (Result<Void, any Error>) -> Void] = [:]
    }

    private let state = Mutex(State())

    /// Whether `open()` has been called. Honest only for asserting an event
    /// did *not* happen — to assert one did, `await wait()`, because a
    /// positive sample still races the writer.
    var isOpen: Bool { state.withLock { $0.open } }

    /// Opens the gate and releases every waiter, present and future.
    /// Idempotent, and deliberately synchronous so it can be signalled from
    /// contexts that cannot `await` — `withTaskCancellationHandler`'s
    /// `onCancel` among them.
    func open() {
        let waiters = state.withLock { state in
            state.open = true
            defer { state.waiters.removeAll() }
            return Array(state.waiters.values)
        }
        for resume in waiters { resume(.success(())) }
    }

    /// Returns once `open()` has been called, now or later. Throws
    /// `CancellationError` if the caller is cancelled first — the waiter is
    /// removed before it resumes, so a released wait can never also be
    /// resumed by a later `open()`.
    func wait() async throws {
        if isOpen { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                let resolution: Result<Void, any Error>? = state.withLock { state in
                    if state.open { return .success(()) }
                    // The cancel could already have run its handler before
                    // this task got here — resolve now instead of parking a
                    // waiter nothing will ever resume.
                    if Task.isCancelled { return .failure(CancellationError()) }
                    state.waiters[id] = { continuation.resume(with: $0) }
                    return nil
                }
                resolution.map { continuation.resume(with: $0) }
            }
        } onCancel: {
            state.withLock { $0.waiters.removeValue(forKey: id) }?(.failure(CancellationError()))
        }
    }

    /// Returns once `open()` has been called — and only then. The caller's
    /// own cancellation does not release the wait: this is for driving
    /// "work that cannot be cancelled" inside the thing under test, never
    /// for the test's own awaits — use `wait()` there so a stuck wait still
    /// answers to `.timeLimit`.
    func waitIgnoringCancellation() async {
        if isOpen { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let parked = state.withLock { state in
                if state.open { return false }
                state.waiters[UUID()] = { _ in continuation.resume() }
                return true
            }
            if !parked { continuation.resume() }
        }
    }
}
