//
//  SyncNodeIntent.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import AppIntents
import Foundation
import os.log

// Phone and tablet only. NodeApp also builds for Mac, and an automation that
// starts a background node has no purpose there. Excluded at compile time rather
// than by an availability annotation, which would still compile this into the Mac
// build and refuse it only at runtime. See
// Development/Specs/003-node-automation-action/plan.md §2.
#if os(iOS)

/// Skeleton of the "Sync Bitcoin Node" Shortcuts action.
///
/// This is the first step of the rewrite tracked in
/// `Development/Specs/003-node-automation-action/plan.md`. It does no node work
/// yet: it records that it ran and hands back a line of text, which is enough to
/// prove the execution path end to end — the system launches the app in the
/// background, calls `perform()`, and a value comes back into the Shortcuts app.
/// The real behaviour (starting the node, the privacy-network gate, reporting)
/// arrives in later commits per the plan's follow-ups.
///
/// Two shape choices are made here so the later work is a swap, not a rewrite:
///
///   * `openAppWhenRun` stays `false` so the action runs in the background. That
///     is the path an unattended automation actually takes, and the one worth
///     proving. The flag is read by the system before `perform()` runs and cannot
///     be changed at runtime, so it is fixed now rather than discovered later
///     (ADR 0005).
///   * `perform()` stays a thin adapter that returns quickly. When the longer
///     execution window (`LongRunningIntent`, iOS 27) is available and shown to
///     work for an unattended trigger, it can be adopted by conforming this type
///     to it without disturbing the surrounding structure (plan §7).
struct SyncNodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Sync Bitcoin Node"
    static let description = IntentDescription(
        "Starts a background Bitcoin node sync run and reports what happened. Runs without opening the app.")

    /// Left in the background: this action is built for unattended automations,
    /// which never bring the app on screen. See ADR 0005.
    static let openAppWhenRun = false

    private static let log = Logger(subsystem: "dev.21.NodeApp", category: "Shortcut")

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let started = ContinuousClock.now
        Self.log.notice("run: entered (stub)")

        // Nothing to do yet. The line below stands in for the real run, and is
        // deliberately honest that no node was started so a tester is not misled.
        let message = "Sync Bitcoin Node ran (stub — no node started yet)."

        let elapsedMs = Int(started.duration(to: .now) / .milliseconds(1))
        Self.log.notice("run: finished (stub) in \(elapsedMs, privacy: .public) ms")

        return .result(value: message, dialog: IntentDialog(stringLiteral: message))
    }
}

#endif
