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

// Phone and tablet only, same reason as the baseline action (ADR 0005).
#if os(iOS)

// Compiled only by the iOS 27 SDK toolchain. `LongRunningIntent` does not exist in
// the iOS 26 SDK, and a runtime `@available` check cannot rescue a symbol the SDK
// lacks — so an Xcode 26 build (Swift 6.3.3) must skip this file entirely, while an
// Xcode 27 build (Swift 6.4) compiles it. The compiler-version check is a proxy for
// "the iOS 27 SDK is present," which holds because each Xcode ships a fixed
// compiler+SDK pair. CI builds both sides of this fence: the apps' jobs run on the
// xcode-27 image, and one build-only macos-26 row covers the compiled-out side.
// See Development/Specs/003-node-automation-action/plan.md §3.5.
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
    private static let scale: Int64 = 100

    /// How often the run reports "still working" when it has nothing truer to say.
    ///
    /// The system ends an extended run that goes quiet, and about thirty seconds of
    /// silence is enough to trigger it. Five seconds leaves a wide margin without
    /// producing distracting motion.
    private static let heartbeat: Duration = .seconds(5)

    /// How long to wait for the node's first answer.
    ///
    /// Four minutes: this action exists precisely to outlast the roughly 30 seconds
    /// the short-run action lives within, and a locked phone has been measured taking
    /// minutes to load its block index.
    private static let waitForFirstAnswer: Duration = .seconds(240)

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

        let stopped = OSAllocatedUnfairLock(initialState: false)
        let report = try await performBackgroundTask(options: []) {
            Self.log.notice("run: background task begin")
            let report = await Self.runWithHeartbeat(meter: meter)
            // The end card is written here, while the operation is still running:
            // a progress write after it returns can land once the display has
            // already gone — the failure recorded in the note above. The bar is
            // filled only by a run that actually read a node — a run that refused
            // to start, or whose node never answered, did not finish the work the
            // bar describes, and filling it would report the opposite of what
            // happened. The words come from the report's own summary sentence, the
            // one piece of text here written to be read by a person. Which is
            // which is decided in `NodeAutomation`, tested. Skipped on a stopped
            // run: a card the person dismissed needs no epitaph, and the report is
            // about to be thrown away below anyway. The same two signals the
            // cancelled-run throw reads below — the flag `onCancel` sets and this
            // task's own cancellation — because `onCancel` is the one the API
            // actually guarantees.
            if !stopped.withLock({ $0 }) && !Task.isCancelled {
                await meter.finish(
                    NodeAutomation.ending(
                        outcome: report.outcome.plain, summary: report.summary))
            }
            return report
        } onCancel: { reason in
            // Stopped by the person tapping the card's stop button, or by the
            // system running out of patience. The node itself is deliberately
            // left running.
            stopped.withLock { $0 = true }
            Self.log.notice(
                "run: cancelled (\(reason.debugDescription, privacy: .public))")
        }

        let elapsedMs = Int(started.duration(to: .now) / .milliseconds(1))
        Self.log.notice(
            "run: finished \(report.outcome.rawValue, privacy: .public) in \(elapsedMs, privacy: .public) ms"
        )
        if stopped.withLock({ $0 }) || Task.isCancelled {
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
    /// it and cannot go on claiming a dead run is alive.
    @MainActor
    private static func runWithHeartbeat(meter: ProgressMeter) async -> NodeRunReport {
        await withTaskGroup(of: NodeRunReport?.self) { group in
            group.addTask { @MainActor in
                while true {
                    do { try await Task.sleep(for: heartbeat) } catch { return nil }
                    meter.tick()
                }
            }
            group.addTask { @MainActor in
                await NodeRun.perform(
                    session: .shared, waitForFirstAnswer: waitForFirstAnswer
                ) { fraction in
                    meter.advance(to: fraction)
                }
            }
            // The heartbeat only ever finishes by being cancelled, and yields nothing
            // when it does, so the first real value is the run's own report.
            var report: NodeRunReport?
            while let finished = await group.next() {
                if let finished {
                    report = finished
                    break
                }
            }
            group.cancelAll()
            // Reachable only if the work was cut short before producing anything.
            return report ?? NodeRun.noAnswerReport()
        }
    }
}

/// Drives the system's progress card, keeping the bar honest.
///
/// Two rules, both of which exist because the card is the only thing the person can
/// see while the run is unattended. The bar never moves backwards, so a heartbeat
/// that has ticked past where the real work has reached does not cause a visible
/// retreat. And nothing but the end of the run can fill it: a full bar is a claim
/// that the work finished, and only `finish(_:)` is in a position to know whether
/// that is true.
@available(iOS 27.0, *)
@MainActor
final class ProgressMeter {
    private let progress: Progress
    private let scale: Int64
    private var reported: Int64 = 0

    init(progress: Progress, scale: Int64) {
        self.progress = progress
        self.scale = scale
        progress.totalUnitCount = scale
        progress.completedUnitCount = 0
    }

    /// Real progress: how far through the run this is, from 0 to 1.
    func advance(to fraction: Double) {
        report(Int64((fraction * Double(scale)).rounded()))
    }

    /// The heartbeat. One step, meaning no more than "still working".
    func tick() {
        report(reported + 1)
    }

    /// The run is over: say what became of it, and fill the bar only if it earned that.
    func finish(_ ending: NodeAutomation.Ending) {
        progress.localizedDescription = ending.title
        progress.localizedAdditionalDescription = ending.detail
        guard ending.fillsProgressBar else { return }
        reported = scale
        progress.completedUnitCount = scale
    }

    private func report(_ value: Int64) {
        let next = min(max(value, reported), scale - 1)
        reported = next
        progress.completedUnitCount = next
    }
}

#endif
#endif
