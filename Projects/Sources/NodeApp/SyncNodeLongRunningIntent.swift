//
//  SyncNodeLongRunningIntent.swift
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

// Phone and tablet only, same reason as the baseline action (ADR 0005).
#if os(iOS)

// Compiled only by the iOS 27 SDK toolchain. `LongRunningIntent` does not exist in
// the iOS 26 SDK, and a runtime `@available` check cannot rescue a symbol the SDK
// lacks — so the everyday Xcode 26 build (Swift 6.3.3) must skip this file entirely,
// while the Xcode 27 build (Swift 6.4) compiles it. The compiler-version check is a
// proxy for "the iOS 27 SDK is present," which holds because each Xcode ships a fixed
// compiler+SDK pair. See Development/Specs/003-node-automation-action/plan.md §3.5.
#if compiler(>=6.4)

/// "Keep Bitcoin Node Syncing" — a separate action, iOS 27+, that runs past the time
/// limit the short-run action lives within.
///
/// A background action normally gets about 30 seconds; conforming to
/// `LongRunningIntent` and wrapping the work in `performBackgroundTask` lets it run
/// past that while the system shows a progress card (a Live Activity) with a stop
/// button — no card code required. Progress updates are mandatory: they are the
/// heartbeat that keeps the extended run alive, so the run is cancelled if they stop.
///
/// This is a skeleton: it does no node work yet, exactly like the baseline
/// `SyncNodeIntent`. The real start/report lands with the node-start slice, calling
/// the one shared helper both actions will use; only the shape is proven here. The
/// clean-stop hook (`onCancel`) is wired now because it is the exact form the real
/// graceful node shutdown will take, but for now it only logs.
@available(iOS 27.0, *)
struct SyncNodeLongRunningIntent: LongRunningIntent, CancellableIntent {
    // Named to stand on its own, not as a variant of the other action. Two reasons.
    // A person on iOS 27 sees both actions listed, and two entries reading "Sync
    // Bitcoin Node" would be indistinguishable. And this is the action that survives:
    // when the baseline retires, a name like "… (Extended)" would be left referring to
    // a sibling nobody remembers — and renaming it then is not an option, because
    // saved automations find an action by its identifier, so a rename reads as a
    // deletion and breaks them.
    static let title: LocalizedStringResource = "Keep Bitcoin Node Syncing"
    static let description = IntentDescription(
        "Starts the Bitcoin node and keeps it syncing past the usual background time limit, showing progress you can stop at any time. Runs without opening the app.")

    // Runs entirely in the background — this is built for unattended automations
    // (ADR 0005). The type is iOS 27-only, so the modern declaration is all that is
    // needed here; the iOS 18–25 path lives on the baseline `SyncNodeIntent`.
    static let supportedModes: IntentModes = .background

    private static let log = Logger(subsystem: "dev.21.NodeApp", category: "Shortcut")

    // Main-actor isolated for the same reason as the baseline action: it reaches
    // main-actor-owned state (`NodeSession`) once the node work lands, and the heavy
    // work runs off this thread. See plan §3.4.
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let started = ContinuousClock.now
        Self.log.notice("run: entered (long-running stub)")

        // One unit of work; the real run will report finer progress. Set before the
        // extended run so the progress card has something to show immediately.
        progress.totalUnitCount = 1

        let message = try await performBackgroundTask(options: []) {
            // Skeleton body — no node work yet (see the type's doc comment).
            Self.log.notice("run: background task begin (long-running stub)")
            // Names this action, not the other one. The text is handed back to the
            // Shortcuts app and spoken by Siri, so saying "Sync Bitcoin Node" here
            // would report the baseline action's name for a run of this one.
            return "Keep Bitcoin Node Syncing ran (long-running stub — no node started yet)."
        } onCancel: { reason in
            // No node to stop yet; the real graceful shutdown lands with the
            // node-start slice. Logged so a stopped run is visible in the console.
            Self.log.notice(
                "run: cancelled (\(reason.debugDescription, privacy: .public)) (long-running stub)")
        }

        progress.completedUnitCount = 1

        let elapsedMs = Int(started.duration(to: .now) / .milliseconds(1))
        Self.log.notice("run: finished (long-running stub) in \(elapsedMs, privacy: .public) ms")
        return .result(value: message, dialog: IntentDialog(stringLiteral: message))
    }
}

#endif
#endif
