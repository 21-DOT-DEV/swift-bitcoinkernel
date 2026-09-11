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

/// The "Sync Bitcoin Node" Shortcuts action — the one that works on every supported
/// system, within the short time a background action is allowed.
///
/// The work itself is the one shared routine both actions call (`NodeRun.perform`),
/// so this action and the longer-running iOS 27 one cannot drift apart. All this type
/// adds is the declaration of where it runs and how long it is prepared to wait. Part
/// of the rewrite tracked in
/// `Development/Specs/003-node-automation-action/plan.md`.
///
/// Two shape choices worth keeping in view:
///
///   * `openAppWhenRun` stays `false` so the action runs in the background. That
///     is the path an unattended automation actually takes. The flag is read by
///     the system before `perform()` runs and cannot be changed at runtime
///     (ADR 0005).
///   * `perform()` stays a thin adapter that returns quickly, so the longer
///     execution window (`LongRunningIntent`, iOS 27) stays a separate action
///     rather than a mode of this one (plan §7).
struct SyncNodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Sync Bitcoin Node"
    static let description = IntentDescription(
        "Starts the Bitcoin node, lets it sync for the short time a background action is allowed, and reports what happened. Runs without opening the app. On iOS 27, Keep Bitcoin Node Syncing runs for longer.")

    // This action always runs in the background — it is built for unattended
    // automations, which never bring the app on screen (ADR 0005). How to declare
    // that splits by OS: `supportedModes` on iOS 26+, and the older `openAppWhenRun`
    // for iOS 18–25 (this app's oldest-supported OS). Both are declared so the
    // behaviour holds on every supported system. The old flag is marked deprecated in
    // its own declaration to match the iOS 26 SDK and keep the build warning-free;
    // when the app's floor reaches iOS 26 it is removed and only `supportedModes`
    // remains (plan §7).
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    @available(iOS, deprecated: 26.0, message: "Superseded by supportedModes; kept for iOS 18–25.")
    static var openAppWhenRun: Bool { false }

    private static let log = Logger(subsystem: "dev.21.NodeApp", category: "Shortcut")

    /// Runs on the main actor (the thread that owns user-interface state). The
    /// process-owned `NodeSession` this action reaches at the later start step is
    /// `@MainActor`-isolated, and under Swift 6 an un-isolated `perform()` cannot
    /// touch it. Isolating the whole method is the right call here: it mostly
    /// orchestrates main-actor state, while the node's heavy work runs on its own
    /// background thread and every wait is an `await` that frees this thread. Any
    /// future heavy or synchronous step added here must be pushed off the main actor
    /// explicitly (for example a detached task), never run inline. See
    /// Development/Specs/003-node-automation-action/plan.md §3.4.
    ///
    /// How long this waits for the node's first answer: a background-launched action
    /// gets roughly 30 seconds in total, so 20 leaves room to read the node and return
    /// rather than being cut off mid-report. On a locked phone the node has been
    /// measured taking minutes to load its block index, so running out of time here is
    /// the ordinary case, not a failure — the run says so and leaves the node coming up.
    /// "Keep Bitcoin Node Syncing" on iOS 27 is the action that can actually wait.
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<NodeRunReport>
        & ProvidesDialog
    {
        let started = ContinuousClock.now
        let report = await NodeRun.perform(waitForFirstAnswer: .seconds(20))
        let elapsedMs = Int(started.duration(to: .now) / .milliseconds(1))
        Self.log.notice(
            "run: finished \(report.outcome.rawValue, privacy: .public) in \(elapsedMs, privacy: .public) ms"
        )
        return .result(value: report, dialog: IntentDialog(stringLiteral: report.summary))
    }
}

#endif
