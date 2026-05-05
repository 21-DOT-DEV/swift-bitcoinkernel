//
//  WaitFor.swift
//  21-DOT-DEV/Bitcoin
//
//  Shared async polling helper for state-convergence assertions. Swift
//  Testing does not (as of this writing) ship a native primitive for
//  waiting on an `@Observable` predicate to flip; `confirmation` is for
//  discrete event callbacks, not state observation.
//
//  Copyright (c) 2026 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

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
