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

/// The "Sync Bitcoin Node" Shortcuts action — the one that works on every
/// supported system, inside the short window a background action is allowed.
///
/// The work itself is the one routine the actions share (`NodeRun.perform`),
/// so this action and the iOS 27 one cannot drift apart — this one calls it
/// today, and the longer-running one's wiring lands in the next delivery slice.
/// All this type adds is the declaration of where it runs and how long it is
/// prepared to wait. Part of the rewrite tracked in
/// `Development/Specs/003-node-automation-action/plan.md`.
///
/// Two shape choices worth keeping in view:
///
///   * `openAppWhenRun`/`supportedModes` keep the action in the background —
///     the path an unattended automation actually takes (ADR 0005). The flag is
///     read by the system before `perform()` runs and cannot change at runtime.
///   * This action has **no progress display** — that exists only on the iOS 27
///     `LongRunningIntent` — so its only completion signal is returning. When a
///     run finds a node still coming up, it reports "still starting" and
///     returns rather than holding the window open: a locked phone has been
///     measured taking minutes to load the block index, and Apple's energy
///     guidance is to end background work the moment it is done rather than
///     waiting to be suspended. The node keeps coming up regardless, and the
///     next run sees it.
struct SyncNodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Sync Bitcoin Node"
    static let description = IntentDescription(
        "Starts the Bitcoin node and reports the result within the short time a background action is allowed — a node still coming up when time runs out is left running. Runs without opening the app. On iOS 27, Keep Bitcoin Node Syncing runs for longer.")

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

    /// How long to wait for the node's first answer after starting one — or
    /// finding one already starting.
    ///
    /// Two seconds, which in practice means "do not wait": a node this run just
    /// started must load its block index before it can answer — measured at
    /// 12–14 seconds unlocked and 47–121 seconds locked — so no wait this window
    /// can afford would see it answer. The small budget exists for the other
    /// path: a node *already* starting (left coming up by an earlier run, or by
    /// the app) can be moments from answering, and catching that costs at most
    /// two seconds of a roughly thirty-second window. A run whose wait runs out
    /// reports "still starting" — an expected outcome, not an error — and leaves
    /// the node coming up. The wait is conditional by construction: a node found
    /// already running is read in full regardless of this budget, with each
    /// question bounded on its own inside `NodeRun`.
    private static let waitForFirstAnswer: Duration = .seconds(2)

    /// Runs on the main actor (the thread that owns user-interface state). The
    /// process-owned `NodeSession` this action reaches is `@MainActor`-isolated,
    /// and under Swift 6 an un-isolated `perform()` cannot touch it. Isolating
    /// the whole method is the right call here: it mostly orchestrates
    /// main-actor state, while the node's heavy work runs on its own background
    /// thread and every wait is an `await` that frees this thread. Any future
    /// heavy or synchronous step added here must be pushed off the main actor
    /// explicitly (for example a detached task), never run inline. See
    /// Development/Specs/003-node-automation-action/plan.md §3.4.
    ///
    /// What a stopped run hands back is decided here, at the boundary, rather
    /// than inside `NodeRun`: the run maps cancellation to a `.noAnswer` report
    /// — a completed result — so that nothing in flight has to be unwound. But a
    /// returned value can flow into the next step of someone's automation as if
    /// it were a measurement, and "the node did not answer" is the wrong thing
    /// for a chain to learn from a run the person stopped. The AppIntents signal
    /// for a cancelled run is a thrown error, so cancellation is converted back
    /// into one here. The iOS 27 action applies the same rule when its wiring
    /// lands.
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<NodeRunReport>
        & ProvidesDialog
    {
        let started = ContinuousClock.now
        let report = await NodeRun.perform(
            session: .shared, waitForFirstAnswer: Self.waitForFirstAnswer)
        let elapsedMs = Int(started.duration(to: .now) / .milliseconds(1))
        Self.log.notice(
            "run: finished \(report.outcome.rawValue, privacy: .public) in \(elapsedMs, privacy: .public) ms"
        )
        if Task.isCancelled {
            Self.log.notice("run: cancelled — reporting the run as cancelled, not as a result")
            throw CancellationError()
        }
        return .result(
            value: report, dialog: IntentDialog(stringLiteral: report.summary))
    }
}

#endif
