//
//  ProgressMeter.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

// iOS-only for the same reason as SyncNodeLongRunningIntent.swift: the progress
// card it drives exists only there, and the file requires the same toolchain —
// the iOS 27 SDK (Xcode 27+).
#if os(iOS)

/// Drives the system's progress card, keeping the bar honest.
///
/// Three rules, all of which exist because the card is the only thing the person
/// can see while the run is unattended. The bar never moves backwards, so a
/// heartbeat that has ticked past where the real work has reached does not cause
/// a visible retreat. The heartbeat's total contribution is capped at half the
/// bar, so heartbeats alone can never carry it past halfway: a bar creeping
/// toward full during a long silent wait would claim the run is nearly done when
/// it may barely have started. And nothing but the end of the run can fill it:
/// a full bar is a claim that the work finished, and only `finish(_:)` is in a
/// position to know whether that is true. The ceiling is functional as well as
/// honest: it keeps `Progress.isFinished` false for the whole run, so anything
/// keying off the standard property sees a run still in progress until
/// `finish(_:)` says otherwise.
///
/// The cap is on the heartbeat's *contribution*, not its landing spot: a run
/// genuinely past halfway can still absorb up to half a bar of heartbeat during
/// a later silence, so the displayed figure can exceed real progress by that
/// much — and a run that stalls past halfway can creep to just under full,
/// where it will read "nearly done". That is the price of a liveness signal
/// whose only currency is a new value — `completedUnitCount` is an integer,
/// and there is nothing smaller to spend.
@available(iOS 27.0, *)
@MainActor
final class ProgressMeter {
    private let progress: Progress
    private let scale: Int64
    private var reported: Int64 = 0

    /// How much of the bar the heartbeat has bought so far — the contribution the
    /// honesty rule caps, rather than the position it happens to land on.
    private var heartbeatUnits: Int64 = 0

    /// Whether a real report landed since the last heartbeat tick. When one did,
    /// the tick is skipped: that report already wrote a new value, so spending a
    /// heartbeat unit on top of it buys nothing — and this is what lets the
    /// budget survive a run of any length rather than draining on wall-clock
    /// time. Fifty units is roughly 250 seconds of *accumulated* silence; the
    /// longest silent stretch the run is designed to produce is bounded by the
    /// node-question budget (~10 seconds), so the budget is spent only where a
    /// genuinely undocumented stretch would otherwise go quiet.
    private var realReportSinceLastTick = false

    init(progress: Progress, scale: Int64) {
        self.progress = progress
        self.scale = scale
        progress.totalUnitCount = scale
        progress.completedUnitCount = 0
    }

    /// Real progress: how far through the run this is, from 0 to 1.
    func advance(to fraction: Double) {
        // A non-finite fraction would crash `Int64(_:)` — an unforced trap inside
        // an unattended background action is the worst available failure mode,
        // so the report is dropped as if it never arrived. Finite-but-huge
        // values trap the same conversion, so the fraction is clamped first —
        // matching `Progress`'s own clamping convention.
        guard fraction.isFinite else { return }
        let clamped = min(max(fraction, 0), 1)
        // A report that changes nothing wrote nothing: it cannot count as the
        // fresh value that covers the next tick, or a run pinned at one figure
        // (the long 0.9 plateau at the end of a maximum-length wait) would
        // suppress the heartbeat for the whole stretch.
        if report(Int64((clamped * Double(scale)).rounded())) {
            realReportSinceLastTick = true
        }
    }

    /// The heartbeat. One step, meaning no more than "still working". Each tick
    /// writes a *new* value — the only thing the system is documented to watch
    /// for the extended-run liveness check — while its *total* contribution
    /// stays capped at half the bar. Skipped when a real report just landed:
    /// the run is not silent, so there is nothing to say over it. One ceiling
    /// applies: at `scale - 1` a new value is impossible, so the tick is a
    /// same-value write that buys nothing — and spends nothing.
    func tick() {
        guard !realReportSinceLastTick else {
            realReportSinceLastTick = false
            return
        }
        guard heartbeatUnits < scale / 2 else { return }
        if report(reported + 1) {
            heartbeatUnits += 1
        }
    }

    /// The run is over: say what became of it, and fill the bar only if it earned that.
    func finish(_ ending: NodeAutomation.Ending) {
        progress.localizedDescription = ending.title
        progress.localizedAdditionalDescription = ending.detail
        guard ending.fillsProgressBar else { return }
        reported = scale
        progress.completedUnitCount = scale
    }

    /// Writes `value`, clamped to the bar's range and floored at the current
    /// position. Returns whether the write actually moved the bar — callers
    /// use it to tell a fresh value (which the system counts as a sign of life)
    /// from a same-value write (which it may not).
    @discardableResult
    private func report(_ value: Int64) -> Bool {
        // The floor is `reported` itself, not the capped value: after `finish`
        // set the bar to full, a late report must still be unable to move it
        // backwards — rule one is structural, not a matter of call order.
        let next = max(reported, min(value, scale - 1))
        let changed = next != reported
        reported = next
        progress.completedUnitCount = next
        return changed
    }
}

#endif
