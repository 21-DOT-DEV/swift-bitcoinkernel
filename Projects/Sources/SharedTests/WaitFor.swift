//
//  WaitFor.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

//  Shared async polling helper for state-convergence assertions. Swift
//  Testing does not (as of this writing) ship a native primitive for
//  waiting on an `@Observable` predicate to flip; `confirmation` is for
//  discrete event callbacks, not state observation.
//
//  ── REACH FOR AN INJECTED CLOCK FIRST ──────────────────────────────────
//
//  This polls the REAL clock, so every call spends real seconds and its
//  timeout is a bet on how loaded the machine is. That bet has lost here
//  twice: `TorViewModelRaceTests` timed out on CI (runs 27073490520 and
//  27059121579), and a later run stalled seven seconds on a test that only
//  compares two strings.
//
//  If the thing you are waiting on is driven by a `Clock` — a retry
//  backoff, a poll interval, any `sleep` — inject a `TestClock` and advance
//  it instead. `TorViewModel` (`clock:`) and `KernelAppViewModel` (`clock:`)
//  both take one for exactly this. Virtual time cannot be starved by a busy
//  runner. As of this writing that migration left this helper with ZERO
//  callers; it is kept as the escape hatch for waits genuinely outside any
//  clock's control (a real filesystem event, a third-party callback).
//
//  What it is NOT for: a stand-in for `Task.sleep(for:)` with a bigger
//  number. If you find yourself widening a timeout to make CI pass, the
//  wait belongs on a clock you control.

import Foundation
import Testing

// MARK: - WaitForTimeoutError

/// Thrown by ``waitFor(timeout:pollEvery:_:sourceLocation:)`` when the
/// timeout elapses. Propagates via `try await` so the test body stops
/// executing instead of continuing with stale state.
struct WaitForTimeoutError: Error {
    let timeout: Duration
}

// MARK: - waitFor

/// Polls `predicate` until it returns true or `timeout` elapses.
///
/// Used instead of magic `Task.sleep(for:)` values when a test asserts
/// on state that becomes true asynchronously.
///
/// Fails the test (via `Issue.record`) and throws ``WaitForTimeoutError``
/// on timeout — both to mark the failure and to halt the awaiting body
/// so downstream assertions don't cascade and obscure the real issue.
///
/// - Parameters:
///   - timeout: Maximum time to wait before failing.
///   - pollEvery: Interval between predicate evaluations (default 10ms).
///   - predicate: Main-actor-isolated snapshot check. Must be cheap.
@MainActor
func waitFor(
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
