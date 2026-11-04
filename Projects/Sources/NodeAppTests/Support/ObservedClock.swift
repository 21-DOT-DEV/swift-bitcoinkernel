//
//  ObservedClock.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

// `NodeRun` and `NodeRunReport` exist only in phone and tablet builds — the
// same compile-time gate as the sources, so these helpers are empty on a
// Mac build.
#if os(iOS)

/// Forwards to a `ManualClock`, reporting each sleep request — and its
/// tolerance — before it parks. The oracle for "this wait asked the injected
/// clock": a sleep spelled `Task.sleep` or a deadline measured on
/// `ContinuousClock.now` never reaches this wrapper, which is what lets a
/// test prove the seam is wired rather than merely present.
struct ObservedClock: Clock {
    typealias Instant = ManualClock.Instant
    let base: ManualClock
    let onSleep: @Sendable (Instant, Duration?) -> Void
    var now: Instant { base.now }
    var minimumResolution: Duration { base.minimumResolution }
    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        onSleep(deadline, tolerance)
        try await base.sleep(until: deadline, tolerance: tolerance)
    }
}

#endif
