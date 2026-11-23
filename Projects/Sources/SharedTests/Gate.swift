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
/// A gate ends one of two ways. `open()` says the event happened.
/// `abandon()` says it never will: a waiter is released with `Abandoned`
/// instead of parking until `.timeLimit`, and the gate never reads as open,
/// so "the gate opened" keeps meaning "the event happened".
///
/// The rule every test that starts the code under test in a `Task` follows:
/// the task's `defer` abandons each checkpoint gate the test waits on and
/// opens the gate that reports the run itself is over.
///
///     let run = Task { @MainActor in
///         defer { napRequested.abandon(); done.open() }
///         return await NodeRun.perform(/* ... */)
///     }
///     try await napRequested.wait()   // throws `Abandoned` on an early exit
///
/// Miss the line and nothing fails while the code is right: the gap shows
/// only when a regression ends the run early, as a one-minute timeout in
/// place of a named failure.
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

    /// Thrown by `wait()` on a gate that was abandoned before it opened.
    /// Carries where the wait was written, because a thrown error is
    /// reported against the test as a whole, not the line that threw.
    struct Abandoned: Error, CustomStringConvertible {
        let fileID: String
        let line: Int
        var description: String {
            "Gate abandoned before it opened: the event awaited at "
                + "\(fileID):\(line) can no longer happen"
        }
    }

    private struct State {
        var open = false
        var abandoned = false
        var waiters: [UUID: (Result<Void, any Error>) -> Void] = [:]
    }

    private let state = Mutex(State())

    /// Called each time a `wait()` or `waitIgnoringCancellation()` parks,
    /// after the waiter is registered and outside the lock. The gate's own
    /// tests use it to act once a wait is truly suspended, where a yield
    /// loop could only guess — the same reporter shape `ObservedClock`
    /// gives sleeps.
    private let onWaiterArmed: (@Sendable () -> Void)?

    init(onWaiterArmed: (@Sendable () -> Void)? = nil) {
        self.onWaiterArmed = onWaiterArmed
    }

    /// Whether `open()` has been called. Honest only for asserting an event
    /// did *not* happen — to assert one did, `await wait()`, because a
    /// positive sample still races the writer.
    var isOpen: Bool { state.withLock { $0.open } }

    /// Opens the gate and releases every waiter, present and future.
    /// Idempotent, and deliberately synchronous so it can be signalled from
    /// contexts that cannot `await` — `withTaskCancellationHandler`'s
    /// `onCancel` among them. A gate already abandoned stays abandoned:
    /// the first ending wins.
    func open() {
        let waiters = state.withLock { state -> [(Result<Void, any Error>) -> Void] in
            guard !state.abandoned else { return [] }
            state.open = true
            defer { state.waiters.removeAll() }
            return Array(state.waiters.values)
        }
        for resume in waiters { resume(.success(())) }
    }

    /// Ends the gate without opening it: the event it stands for can no
    /// longer happen. Every `wait()`, parked or future, throws `Abandoned`.
    /// A gate already open stays open: the event did happen, and the first
    /// ending wins. Synchronous for the same reason `open()` is: it runs
    /// in a `defer`.
    func abandon() {
        let waiters = state.withLock { state -> [(Result<Void, any Error>) -> Void] in
            // Keeps "open" and "abandoned" mutually exclusive. No caller can observe
            // the difference today, because every wait checks `open` first and an
            // ended gate has no parked waiters. A mutant that drops this guard
            // survives by design.
            guard !state.open, !state.abandoned else { return [] }
            state.abandoned = true
            defer { state.waiters.removeAll() }
            return Array(state.waiters.values)
        }
        // The location is the waiter's own, filled in where it parked.
        for resume in waiters { resume(.failure(AbandonedWhileParked())) }
    }

    /// What `abandon()` hands a parked waiter. `wait()` turns it into
    /// `Abandoned` with its own location; `waitIgnoringCancellation()`
    /// simply returns.
    private struct AbandonedWhileParked: Error {}

    /// Returns once `open()` has been called, now or later. Throws
    /// `Abandoned` if `abandon()` ended the gate first, naming the line
    /// this wait was written on. Throws `CancellationError` if the caller
    /// is cancelled first — the waiter is removed before it resumes, so a
    /// released wait can never also be resumed by a later `open()`.
    func wait(fileID: String = #fileID, line: Int = #line) async throws {
        if isOpen { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                let resolution: Result<Void, any Error>? = state.withLock { state in
                    if state.open { return .success(()) }
                    if state.abandoned {
                        return .failure(Abandoned(fileID: fileID, line: line))
                    }
                    // The cancel could already have run its handler before
                    // this task got here — resolve now instead of parking a
                    // waiter nothing will ever resume.
                    if Task.isCancelled { return .failure(CancellationError()) }
                    state.waiters[id] = { result in
                        continuation.resume(with: result.mapError {
                            error -> any Error in
                            error is AbandonedWhileParked
                                ? Abandoned(fileID: fileID, line: line) : error
                        })
                    }
                    return nil
                }
                resolution.map { continuation.resume(with: $0) }
                if resolution == nil { onWaiterArmed?() }
            }
        } onCancel: {
            state.withLock { $0.waiters.removeValue(forKey: id) }?(.failure(CancellationError()))
        }
    }

    /// Returns once the gate has ended: opened, or abandoned, since no one
    /// is left to open an abandoned gate and parking on it would leak the
    /// task. The caller's own cancellation does not release the wait:
    /// this is for driving "work that cannot be cancelled" inside the
    /// thing under test, never for the test's own awaits — use `wait()`
    /// there so a stuck wait still answers to `.timeLimit`.
    func waitIgnoringCancellation() async {
        if isOpen { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let parked = state.withLock { state in
                if state.open || state.abandoned { return false }
                state.waiters[UUID()] = { _ in continuation.resume() }
                return true
            }
            if !parked { continuation.resume() }
            if parked { onWaiterArmed?() }
        }
    }
}
