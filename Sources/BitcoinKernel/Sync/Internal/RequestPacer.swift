//
//  RequestPacer.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Enforces a minimum delay between sequential HTTP requests through a single
/// ``EsploraBlockSource`` — prevents rate-limiting by well-behaved public
/// Esplora instances (mempool.space, blockstream.info).
///
/// Expressed on Swift's `ContinuousClock` / `Duration` types for
/// deterministic testing and concurrency safety.
///
/// ### Ownership
///
/// Per-instance ownership — each ``EsploraBlockSource`` owns its own pacer.
/// This keeps tests isolated (parallel test runs don't share pacing state)
/// and matches the intent that rate limits are per-endpoint — two sources
/// pointing at different endpoints shouldn't throttle each other.
actor RequestPacer {
    private let minimumDelay: Duration
    private var earliestNextStart: ContinuousClock.Instant

    init(minimumDelay: Duration) {
        self.minimumDelay = minimumDelay
        self.earliestNextStart = ContinuousClock.now
    }

    /// Atomically reserve the next paced request slot and return the instant
    /// at which the caller should begin its request.
    ///
    /// The caller is expected to `Task.sleep(until:clock:)` until the returned
    /// instant before issuing the request. Because slot reservation is
    /// atomic (actor-serialized) but the sleep happens outside the actor,
    /// N concurrent callers each get a unique slot spaced `minimumDelay`
    /// apart — even if every sleep is in flight simultaneously.
    ///
    /// - Returns: The monotonic-clock instant at which the caller's request
    ///   may begin.
    func reserveNextSlot() -> ContinuousClock.Instant {
        let now = ContinuousClock.now
        let start = now > earliestNextStart ? now : earliestNextStart
        earliestNextStart = start + minimumDelay
        return start
    }
}
