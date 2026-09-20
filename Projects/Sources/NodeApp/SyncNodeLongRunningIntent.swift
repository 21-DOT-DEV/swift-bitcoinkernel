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
import os
import Synchronization

// Phone and tablet only, same reason as the baseline action (ADR 0005).
#if os(iOS)

// Building this file requires the iOS 27 SDK toolchain (Xcode 27+):
// `LongRunningIntent` does not exist in the iOS 26 SDK, and a runtime
// `@available` check cannot rescue a symbol the compiled-against SDK lacks.
// The demo apps declare Xcode 27 their minimum toolchain, so an older Xcode
// fails here loudly rather than silently producing an app that lacks this
// action. The iOS 18–26 *runtime* gate is the `if #available` in
// NodeAppShortcuts.swift, not a compile fence — on those systems the app runs
// with only the baseline action published.
// See Development/Specs/003-node-automation-action/plan.md §3.5.

/// "Keep Bitcoin Node Syncing" — a separate action, iOS 27+, that runs past the time
/// limit the short-run action lives within.
///
/// A background action normally gets about 30 seconds; conforming to
/// `LongRunningIntent` and wrapping the work in `performBackgroundTask` lets it run
/// past that while the system shows a progress card (a Live Activity) with a stop
/// button — no card code required. Progress updates are mandatory: they are the
/// heartbeat that keeps the extended run alive, so the run is cancelled if they stop.
///
/// The work itself is the one shared routine both actions call (`NodeRun.perform`),
/// so the two cannot drift apart; the only things this action adds are the longer
/// time window and the progress card that comes with it.
///
/// The clean-stop hook (`onCancel`) only logs — it ends the run, never the node.
/// Leaving the node up is the feature's posture (ADR 0009), and a node still inside
/// its own start-up cannot service a stop request anyway: the attempt would hang
/// until the system killed the run.
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

    /// Progress is reported in hundredths so the bar moves smoothly across a wait that
    /// may last minutes, rather than jumping from nothing to done.
    ///
    /// Internal rather than private for the test that guards the coupling below:
    /// the meter's half-bar heartbeat budget (derived from this scale), multiplied
    /// by `heartbeat`, must outlast `waitForFirstAnswer` — a change to any of the
    /// three silently shortens the liveness floor otherwise.
    static let scale: Int64 = 100

    /// How often the run reports "still working" when it has nothing truer to say.
    ///
    /// The system ends an extended run that goes quiet, and about thirty seconds of
    /// silence is enough to trigger it. Five seconds leaves a wide margin without
    /// producing distracting motion. See `scale` for the coupling this forms.
    static let heartbeat: Duration = .seconds(5)

    /// How long to wait for the node's first answer.
    ///
    /// Four minutes: this action exists precisely to outlast the roughly 30 seconds
    /// the short-run action lives within, and a locked phone has been measured taking
    /// minutes to load its block index. See `scale` for the coupling this forms.
    static let waitForFirstAnswer: Duration = .seconds(240)

    // Main-actor isolated for the same reason as the baseline action: it reaches
    // main-actor-owned state (`NodeSession`), and the heavy work runs off this
    // thread. See plan §3.4.
    //
    // What a stopped run hands back is decided here, at the boundary — the same
    // rule `SyncNodeIntent` applies. The run maps cancellation to a `.noAnswer`
    // report so nothing in flight has to be unwound, but a returned value can
    // flow into the next step of someone's automation as if it were a
    // measurement, and "the node did not answer" is the wrong thing for a chain
    // to learn from a run the person stopped. The AppIntents signal for a
    // cancelled run is a thrown error, so cancellation is converted back into
    // one before the result is built. The check cannot lean on
    // `Task.isCancelled` alone: the API promises only that `onCancel` runs when
    // the system stops the task, not that this task is the thing cancelled — so
    // `onCancel` records the stop itself.
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<NodeRunReport>
        & ProvidesDialog
    {
        let started = ContinuousClock.now
        Self.log.notice("run: entered")

        // Progress must be advanced from *inside* the run below, repeatedly — it is not
        // decoration. It is the signal that keeps the extended time window open, and a
        // run that stops reporting can be cut short by the system. An earlier version
        // set the total here and the completed count after the run returned, which was
        // wrong twice over: the display sat at 0% for the whole run because the only
        // update arrived once it had already gone, and a real run would have risked
        // being killed by the very mechanism meant to keep it alive. Observed on device.
        let meter = ProgressMeter(progress: progress, scale: Self.scale)
        progress.localizedDescription = NodeAutomation.inProgressTitle

        // The reason the run was stopped, not just that it was: the two callers
        // below need different endings — a card the person dismissed needs no
        // epitaph, but a run the system ended for silence leaves a card nobody
        // dismissed, and that card owes an honest ending.
        let stopped = Mutex<IntentCancellationReason?>(nil)
        let report = try await performBackgroundTask(options: []) {
            Self.log.notice("run: background task begin")
            let report = await Self.runWithHeartbeat(meter: meter) {
                stopped.withLock { $0 != nil }
            }
            // The end card is written here, while the operation is still running:
            // a progress write after it returns can land once the display has
            // already gone — the failure recorded in the note above. The bar is
            // filled only by a run that actually read a node — a run that refused
            // to start, or whose node never answered, did not finish the work the
            // bar describes, and filling it would report the opposite of what
            // happened. The words come from the report's own summary sentence, the
            // one piece of text here written to be read by a person. Which is
            // which is decided in `NodeAutomation`, tested. A timeout gets its own
            // ending — the system ended the run, so nobody dismissed the card —
            // while a stop the person tapped gets none, since a card the person
            // dismissed needs no epitaph; either way the report is about to be
            // thrown away below. The same two signals the cancelled-run throw
            // reads below — the reason `onCancel` sets and this task's own
            // cancellation — because `onCancel` is the one the API actually
            // guarantees. The write may not land if the process suspends first —
            // worth attempting anyway.
            switch stopped.withLock({ $0 }) {
            case .none where !Task.isCancelled:
                meter.finish(
                    NodeAutomation.ending(
                        outcome: report.outcome.plain, summary: report.summary))
            case .userCancelled:
                // The person dismissed the card — it needs no epitaph.
                break
            case .timeout:
                meter.finish(NodeAutomation.timedOutEnding)
            default:
                // A cancellation with no recorded reason (this task cancelled
                // without `onCancel` running), or a reason added after this was
                // written. Unknown is not the person's dismissal, so the card
                // gets the honest cut-short ending rather than freezing.
                Self.log.notice("run: ended without a recognised reason — writing the cut-short ending")
                meter.finish(NodeAutomation.timedOutEnding)
            }
            return report
        } onCancel: { reason in
            // Stopped by the person tapping the card's stop button, or by the
            // system running out of patience. The node itself is deliberately
            // left running.
            stopped.withLock { $0 = reason }
            Self.log.notice(
                "run: cancelled (\(reason.debugDescription, privacy: .public))")
        }

        let elapsedMs = Int(started.duration(to: .now) / .milliseconds(1))
        Self.log.notice(
            "run: finished \(report.outcome.rawValue, privacy: .public) in \(elapsedMs, privacy: .public) ms"
        )
        if stopped.withLock({ $0 != nil }) || Task.isCancelled {
            Self.log.notice("run: cancelled — reporting the run as cancelled, not as a result")
            throw CancellationError()
        }
        return .result(value: report, dialog: IntentDialog(stringLiteral: report.summary))
    }

    /// Runs the work with a heartbeat underneath it.
    ///
    /// The waiting loop inside `NodeRun` reports every half second, but everything
    /// around it is quiet: the device checks, establishing the private network,
    /// launching the node, and reading a node that is already up — whose single
    /// question to the node can itself take thirty seconds before the channel gives
    /// up. Any one of those stretches can exhaust the system's patience on its own.
    /// So a nudge runs underneath the whole thing as a floor, and real reports push
    /// past it whenever the run actually knows something — the bar never moves
    /// backwards, so whichever of the two marks is higher is the one that stands.
    ///
    /// Structured as a task group rather than a loose background task so that when
    /// the work ends — for any reason, including being stopped — the nudge ends with
    /// it and cannot go on claiming a dead run is alive. The direction also
    /// reverses: a stop does not reliably reach the work's own cancellation
    /// checkpoints (the API promises `onCancel` runs, not that this task is the
    /// one cancelled), so the nudge watches the flag too, and its ending the
    /// group is what cancels the work child — a stop tap during preflight then
    /// unwinds the run at `NodeRun`'s next checkpoint instead of running four
    /// more minutes unseen, and a node start already in flight completes or
    /// unwinds exactly as it does under a system-sent cancellation.
    ///
    /// Internal rather than private so tests can drive the group with a stand-in
    /// `work` — first-yield-wins, the heartbeat's nil cancelling the work child,
    /// and the stop flag reaching a `@MainActor` child are the riskiest
    /// mechanics in the action and should not be hardware-only. The defaults
    /// keep the production call site a one-liner.
    @MainActor
    static func runWithHeartbeat(
        meter: ProgressMeter,
        isStopped: @escaping @Sendable () -> Bool,
        heartbeatInterval: Duration = Self.heartbeat,
        work: @escaping @MainActor (@MainActor (Double) -> Void) async -> NodeRunReport = {
            await NodeRun.perform(
                session: .shared, waitForFirstAnswer: waitForFirstAnswer,
                onProgress: $0)
        }
    ) async -> NodeRunReport {
        await withTaskGroup(of: NodeRunReport?.self) { group in
            group.addTask { @MainActor in
                while true {
                    // Checked before the sleep too: a stop that lands while the
                    // group is still setting up should not wait out a full
                    // heartbeat interval to begin unwinding the work child.
                    if isStopped() { return nil }
                    do { try await Task.sleep(for: heartbeatInterval) } catch { return nil }
                    if isStopped() { return nil }
                    meter.tick()
                }
            }
            group.addTask { @MainActor in
                await work { fraction in meter.advance(to: fraction) }
            }
            // Whichever yields first ends the group: the work's report on a
            // completed run, or the heartbeat's nil when the run was stopped or
            // this task cancelled. Leaving the scope cancels the child still
            // running, so a stop propagates into the work itself.
            let report = await group.next().flatMap { $0 }
            group.cancelAll()
            // Nil is reachable only if the run was cut short before producing
            // anything.
            return report ?? NodeRun.noAnswerReport()
        }
    }
}

#endif
