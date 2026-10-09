//
//  NodeRun.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Bitcoin
import Foundation
import os.log

// Phone and tablet only, for the reason recorded in
// Development/Specs/003-node-automation-action/plan.md §2.
#if os(iOS)

import UIKit

/// The one routine both Shortcuts actions call, so their behaviour cannot drift apart.
///
/// Everything here touches the device or the node, which is why it cannot be exercised
/// by automated checks; the decisions it makes live in `NodeAutomation` and
/// `NodePreflight`, which are plain values and are tested. This orchestrates and does
/// no deciding. See `Development/Specs/003-node-automation-action/plan.md` §3.
@MainActor
enum NodeRun {

    private static let log = Logger(subsystem: "dev.21.NodeApp", category: "Shortcut")

    /// The most a single question to the node may take before the run stops
    /// waiting on it.
    ///
    /// The channel used to ask the node a question waits up to thirty seconds
    /// for an answer and cannot be cancelled once asked — it runs to completion
    /// in-process. Left unbounded, one slow question consumes a whole run: the
    /// short action has roughly thirty seconds in total, and roughly thirty
    /// seconds without a progress report is what it takes for the system to end
    /// an extended run as stalled. `withHardTimeout` makes the bound real — the
    /// abandoned question finishes in the background and its answer is dropped.
    /// Ten seconds is a judgment call: long enough that a healthy node answers
    /// comfortably, short enough that the short action's read of an
    /// already-running node (two questions) still fits its window.
    private static let questionBudget: Duration = .seconds(10)

    /// Runs once and reports.
    ///
    /// - Parameters:
    ///   - session: the process-owned node and private-network controllers — always
    ///     `.shared` in practice (its initializer is private). Passed explicitly so
    ///     the dependency stays visible at the call site rather than baked into the
    ///     signature.
    ///   - waitForFirstAnswer: how long to keep asking the node whether it is up
    ///     after this run starts one — or finds one already starting. The two
    ///     actions pass different budgets: the short-run action has roughly half
    ///     a minute in total and passes a minimal budget — a locked phone has
    ///     been measured taking minutes to load the block index, so waiting for
    ///     it is not a service the short window can provide — while the iOS 27
    ///     action may run for minutes. A wait that runs out is an expected
    ///     outcome, not an error. Only the waiting paths consult this: a node
    ///     that is already answering is read straight away, each question
    ///     bounded by `questionBudget`.
    ///   - onProgress: called as the wait proceeds, with a fraction from 0 to 1.
    ///     The iOS 27 action forwards this to its progress display; advancing it
    ///     is also what keeps that longer time window open. Never call it from
    ///     inside a `withHardTimeout` operation: an abandoned question outlives
    ///     the run, so a report written there can land after `perform` has
    ///     returned and the progress display it feeds is already gone.
    static func perform(
        session: NodeSession,
        waitForFirstAnswer: Duration,
        onProgress: @MainActor (Double) -> Void = { _ in }
    ) async -> NodeRunReport {
        // Every setting the run is allowed to see is read once, here, before the
        // first suspension point: a run spans tens of seconds, and a toggle
        // landing in that window must not rewrite what it launches — a changed
        // `bitcoin_network` would start a chain the launch decision below never
        // covered, and a changed `tor_enabled` would decide privacy on intent
        // the person has already reversed. Screens keep reading live; a run
        // sees this snapshot.
        //
        // One deliberate exception: the privacy *floor* is re-read at the
        // launch boundary in `start` — the only read of a live setting this
        // file makes. A toggle flipped *on* mid-run must never be answered
        // with a direct connection (that direction leaks the person's
        // address), while a toggle flipped *off* after the snapshot required
        // privacy still requires it — a decline is recoverable and a leak is
        // not. See `start` and ADR 0006.
        let settings = DaemonConfig.Snapshot(reading: .standard)
        // The step decision weighs the snapshot's privacy setting; `start`
        // tightens it to snapshot-or-live at the launch boundary — the two
        // deliberately differ, so this local keeps the narrower name.
        let snapshotPrivacy = settings.torEnabled
        log.notice("run: entered, snapshot says privacy network enabled = \(snapshotPrivacy, privacy: .public)")

        // A cancelled task still runs until it checks — a run called off before
        // it began would otherwise launch the node (or the private network) on
        // its way out, the very act the cancel was meant to prevent. Check
        // before the side effects, not just before the reports: here on entry,
        // and again right before the switch, because the device-condition read
        // in between is the one stretch that suspends (its bounded wait on the
        // first network report).
        guard !Task.isCancelled else { return noAnswerReport() }

        // Idempotent, and belt-and-braces: the watcher is started at process launch, but
        // this is the one path that runs with no window, so it does not rely on that.
        NetworkCostMonitor.shared.start()

        let step = NodeAutomation.step(
            nodeState: session.node.nodeState,
            privacyEnabled: snapshotPrivacy,
            privacyReady: session.tor.isReady
        )

        if NodeAutomation.consultsDeviceConditions(for: step),
            let refusal = NodePreflight.refusal(for: await readConditions())
        {
            log.notice("run: declined — \(String(describing: refusal), privacy: .public)")
            return declined(reason: refusal.message)
        }

        // The second checkpoint promised above: the device-condition read can
        // spend up to two seconds suspended — plenty of window for a stop to
        // arrive. Without this, a called-off run could still reach the branch
        // that starts the private network, and a consensus download over
        // whatever link is current is precisely the act these checks exist to
        // prevent.
        guard !Task.isCancelled else { return noAnswerReport() }

        switch step {
        case .reportExistingNode:
            // Never interrupt a node someone started themselves: read it and leave it
            // alone (ADR 0005).
            log.notice("run: a node is already running — reading and leaving it alone")
            return await report(session: session, onProgress: onProgress)

        case .waitForStartingNode:
            // Already on its way up: nothing to start, and nothing to read until
            // its block index loads — so the run waits on it exactly like a node
            // it started itself.
            log.notice("run: a node is already starting — waiting on it")
            return await waitForStarting(
                session: session, within: waitForFirstAnswer, onProgress: onProgress)

        case .waitForPrivateNetwork:
            // The step was decided before the device-condition read, which can
            // suspend for seconds — long enough for an in-flight bootstrap to
            // finish. A network that is ready now means there is nothing to
            // wait for, and declining "not ready" would be a lie at report
            // time; take the start path and let its own checks run.
            if session.tor.isReady {
                return await start(
                    session: session, settings: settings,
                    waitForFirstAnswer: waitForFirstAnswer, onProgress: onProgress)
            }
            // Spend the run establishing the private network rather than starting on a
            // direct connection, which would expose the person's home network address
            // after they asked it not to. Which sentence the person gets — and the
            // log — depends on the live setting: still on means the network is
            // genuinely coming up; switched off mid-run means nothing is being
            // established, and saying so would be a lie in both places.
            let stillEnabled = session.startTorIfStillEnabled()
            if stillEnabled {
                log.notice("run: private network not ready — starting it, not starting the node")
            } else {
                log.notice("run: private network was turned off mid-run — not starting the node")
            }
            return declined(
                reason: NodeAutomation.StartRefusal(stillEnabled: stillEnabled).message)

        case .startNode:
            return await start(
                session: session, settings: settings,
                waitForFirstAnswer: waitForFirstAnswer, onProgress: onProgress)
        }
    }

    // MARK: - Starting

    private static func start(
        session: NodeSession,
        settings: DaemonConfig.Snapshot,
        waitForFirstAnswer: Duration,
        onProgress: @MainActor (Double) -> Void
    ) async -> NodeRunReport {
        // Privacy fails closed at the launch boundary — the one place this file
        // re-reads a live setting beside the snapshot. If the person turned Tor
        // *on* after the run entered (snapshot says off, live says on), starting
        // on a direct connection now would leak their home network address
        // moments after they asked for privacy. Turned *off* mid-flight, the
        // run declines instead: the preference write lands a step before the
        // screen tears the network down, so a still-reporting endpoint cannot
        // be trusted — `startArguments` declines the split before the proxy
        // floor is even checked. The decision itself lives in `NodeAutomation`
        // and is tested (ADR 0006).
        let liveEnabled = UserDefaults.standard.bool(forKey: "tor_enabled")
        let privacyEnabled = NodeAutomation.requiresPrivateNetwork(
            snapshotEnabled: settings.torEnabled,
            liveEnabled: liveEnabled)
        // `buildArguments` gates `-proxy=` on the snapshot's own tor flag, so it
        // is fed the effective one — a live-on tightening must actually put the
        // proxy in the arguments, not just pass the check below.
        var effectiveSettings = settings
        effectiveSettings.torEnabled = privacyEnabled
        let arguments: [String]
        do {
            arguments = try NodeAutomation.startArguments(
                snapshotEnabled: settings.torEnabled,
                liveEnabled: liveEnabled,
                // The address is offered only while the network is actually
                // usable: a Tor on its way down keeps reporting its old endpoint
                // until teardown finishes, so `proxyAddress` alone would bind
                // the node to a proxy that dies seconds after launch — and with
                // `-proxy=` set the daemon has no direct fallback, which makes a
                // dead launch reported as started strictly worse than a decline.
                proxyAddress: session.tor.isReady ? session.tor.proxyAddress : nil,
                build: {
                    DaemonConfig.buildArguments(settings: effectiveSettings, torProxy: $0)
                })
        } catch let refusal {
            // The refusal exists because the shared argument builder simply omits
            // the proxy when no address is present, which unattended would start
            // the node on a direct connection. It is live rather than vestigial:
            // the device-condition read suspends on the first network report, and
            // the private network can drop — or be switched off — in that window,
            // after the step decision has already committed to starting. (While
            // that read could not suspend, the check genuinely was unreachable.)
            // `throws(StartRefusal)` lets the compiler prove this is the only
            // branch — report the verdict the builder rendered rather than
            // re-derive it from a second read — and re-arm the network only for
            // the not-ready answer, whose sentence promises it is being
            // established; a turned-off refusal promises nothing, and nudges
            // nothing.
            log.error("run: refused to start — \(String(describing: refusal), privacy: .public)")
            if refusal == .privateNetworkNotReady { session.startTorIfStillEnabled() }
            return declined(reason: refusal.message)
        }

        // The height recorded before this run, so the report can say what arrived since
        // — which spans the minutes the node kept running after an earlier run ended.
        // Captured before the wait, not after: once the node reaches `.running` its
        // own sync poll begins overwriting the observational store the baseline
        // can still fall back to.
        let previous = lastRunBaseline()

        // The last checkpoint before the side effect: the condition read and the
        // argument build suspend nowhere, but a run cancelled in that window would
        // still launch the node it was called off to prevent.
        guard !Task.isCancelled else { return noAnswerReport() }

        // `start()` refuses anything but `.stopped`. Something else can have
        // moved the node off it while the device-condition read suspended —
        // another run, the app's own Start button, or a config change's
        // restart — and reporting `.started` then claims work this run did
        // not do, the exact distinction `waitForStarting` exists to keep.
        // Take that path instead: it waits on whoever's node is coming up and
        // reports what it finds honestly.
        guard session.node.start(
            arguments: arguments,
            torSession: privacyEnabled ? session.tor.sessionID : nil,
            torSocksPort: privacyEnabled
                ? session.tor.socksEndpoint.flatMap { UInt16(exactly: $0.port) } : nil
        ) else {
            log.notice("run: node moved off stopped during the condition read — waiting on whoever started it")
            return await waitForStarting(
                session: session, within: waitForFirstAnswer, onProgress: onProgress)
        }
        log.notice("run: node start requested")

        guard
            let reading = await awaitFirstAnswer(
                session: session, within: waitForFirstAnswer, onProgress: onProgress)
        else {
            // The wait can also end before its deadline: the run was cancelled, the
            // node was stopped from the app mid-wait, or an in-flight answer was
            // discarded because the world had already changed. Claiming "had not
            // come up yet" then would suggest the node is still on its way — it is
            // not. Same check `report()` runs, with the same report for a run that
            // got nothing it can stand behind.
            guard answerIsStillWanted(session: session) else {
                log.notice("run: wait ended early — run cancelled or node stopped")
                return noAnswerReport()
            }
            log.notice("run: node had not come up within the time available — left running")
            return didNotComeUpReport()
        }

        log.notice("run: node answered at block \(reading.height, privacy: .public)")
        return await measuredReport(
            outcome: .started, previous: previous, reading: reading,
            session: session, onProgress: onProgress)
    }

    /// Waits on a node that is already coming up — started by an earlier run that
    /// ran out of time, or by the app itself — and reports what it finds.
    ///
    /// The wait is the same one a just-started node gets: `budget` bounds it and
    /// every question inside it is bounded by `questionBudget`. An answer is
    /// reported `.alreadyRunning` rather than `.started` — this run did not start
    /// anything — and a wait that runs out is `.didNotComeUp`: "still starting"
    /// is literally true whoever started it.
    private static func waitForStarting(
        session: NodeSession,
        within budget: Duration,
        onProgress: @MainActor (Double) -> Void
    ) async -> NodeRunReport {
        // Captured before the wait for the same reason `start` captures it: once
        // the node reaches `.running` its own sync poll overwrites the
        // observational fallback the baseline can read.
        let previous = lastRunBaseline()
        guard
            let reading = await awaitFirstAnswer(
                session: session, within: budget, onProgress: onProgress)
        else {
            guard answerIsStillWanted(session: session) else {
                log.notice("run: wait ended early — run cancelled or node stopped")
                return noAnswerReport()
            }
            log.notice("run: node had not come up within the time available — left starting")
            return didNotComeUpReport()
        }
        log.notice("run: starting node answered at block \(reading.height, privacy: .public)")
        return await measuredReport(
            outcome: .alreadyRunning, previous: previous, reading: reading,
            session: session, onProgress: onProgress)
    }

    /// Keeps asking the node whether it is up, giving up at the deadline.
    ///
    /// A `nil` here means only "no usable answer arrived" — the deadline may have
    /// expired, or the wait may have ended early because the run was cancelled, the
    /// node was stopped, or an answer landed after it was still wanted. Callers
    /// distinguish the cases with `answerIsStillWanted`, not by assuming a `nil`
    /// means the node is still coming up.
    ///
    /// Asks the node directly rather than watching the app's own "running" flag, which
    /// is set by a start-up loop that backs off to two-second gaps — up to two seconds
    /// of a short run would otherwise be spent with the node already up and nobody
    /// looking. Asking directly also yields the height without a second round trip.
    ///
    /// Each question is bounded by `withHardTimeout` at the smaller of the time
    /// remaining and `questionBudget`. The remaining-time half makes the deadline a
    /// hard one — a question cannot be called back once asked, so without its own
    /// bound the loop would sit inside it past the deadline and never notice. The
    /// ceiling half keeps one slow question from consuming a long wait whole: the
    /// iOS 27 action waits minutes, and a question parked for all of them reports
    /// nothing in between.
    ///
    /// One deadline is computed up front rather than accumulating intervals, state is
    /// re-read every time rather than assumed (someone may open the app and stop the
    /// node mid-wait), and the sleep is interruptible so a stopped run exits promptly.
    private static func awaitFirstAnswer(
        session: NodeSession,
        within budget: Duration,
        onProgress: @MainActor (Double) -> Void
    ) async -> NodeAutomation.LiveReading? {
        let reader = session.reader
        let started = ContinuousClock.now
        let deadline = started.advanced(by: budget)
        let budgetSeconds = Double(budget / .milliseconds(1)) / 1000

        while ContinuousClock.now < deadline {
            if Task.isCancelled { return nil }
            if session.node.nodeState.isStoppedOrStopping { return nil }
            let remaining = ContinuousClock.now.duration(to: deadline)
            let info = try? await withHardTimeout(min(remaining, questionBudget)) {
                try await reader.blockchainInfo()
            }
            if let info {
                // Re-read both facts now the answer is actually here, rather than
                // trusting the check at the top of this pass. A question already in
                // flight cannot be called back, so its answer can land after the run
                // was stopped or after someone opened the app and shut the node down.
                // Reporting it then would claim a success contradicting what they just
                // did. The decision itself lives in `NodeAutomation` and is tested.
                guard answerIsStillWanted(session: session) else { return nil }
                // Nine-tenths rather than full: the peer-count question still runs
                // after the answer lands, and the bar keeps a notch in reserve for
                // it — the milestones exist so movement corresponds to something
                // real. The wait loop below caps at the same mark so the bar never
                // steps backwards.
                onProgress(0.9)
                return NodeAutomation.reading(from: info)
            }
            let elapsed = Double(started.duration(to: .now) / .milliseconds(1)) / 1000
            onProgress(budgetSeconds > 0 ? min(0.9, elapsed / budgetSeconds) : 0)
            // The nap is capped by the time left rather than fixed at half a
            // second: an uncapped sleep can outlive the deadline by most of its
            // length — a two-second wait was observed ending at ~2.2s — which
            // would make the deadline a soft one in the one place this loop
            // promises it is hard.
            let nap = min(
                .milliseconds(500), ContinuousClock.now.duration(to: deadline))
            if nap > .zero {
                do { try await Task.sleep(for: nap) } catch { return nil }
            }
        }
        return nil
    }

    // MARK: - Reading

    /// Reads a node that is already up.
    ///
    /// Takes `onProgress` for the same reason the waiting loop does. This path used to
    /// report nothing at all, so an extended run spent the whole read showing an empty
    /// bar and then jumped to full — the exact shape the action was written to avoid.
    /// Each question is bounded by `questionBudget` for the same reason the waiting
    /// loop's are: an unbounded one could be the only thing between the run and a
    /// thirty-second silence the system reads as a stall. The repeating nudge in the
    /// iOS 27 action is what guarantees the run keeps reporting; these milestones
    /// exist so the movement corresponds to something real rather than being pure
    /// invention.
    private static func report(
        session: NodeSession,
        onProgress: @MainActor (Double) -> Void
    ) async -> NodeRunReport {
        let reader = session.reader
        onProgress(0.1)
        let info = try? await withHardTimeout(questionBudget) {
            try await reader.blockchainInfo()
        }
        guard let info else {
            // It says it is running but will not answer — the anomaly most worth
            // a log line on an unattended run (daemon alive, RPC dead).
            log.notice("run: node claims to be running but did not answer")
            return noAnswerReport()
        }
        // The answer is real but may describe a world that no longer exists: the run
        // can have been cancelled, or the node stopped from the app, while the
        // question was in flight — and a question once asked cannot be called back.
        // The same re-check the waiting loop runs, with the same report for a
        // discarded answer: the run got nothing it can stand behind.
        guard answerIsStillWanted(session: session) else { return noAnswerReport() }
        onProgress(0.6)
        return await measuredReport(
            outcome: .alreadyRunning, previous: lastRunBaseline(),
            reading: NodeAutomation.reading(from: info),
            session: session, onProgress: onProgress)
    }

    /// The report for a run holding a real reading: asks the last question
    /// (the peer count, bounded like every other), and fills the bar only once
    /// nothing is still outstanding.
    ///
    /// `previous` is captured by the caller before the wait it is about to
    /// do: the starting paths read it before `awaitFirstAnswer`, and
    /// `report` reads it just before this call — after the node question,
    /// before the peer-count one. It reads the run-owned `last_run_*`
    /// baseline — written only by a result that is actually returned — so the
    /// node's own sync poll (which writes the observational `last_known_*`
    /// every 30 seconds) can never collapse the delta toward zero just because
    /// the app was alive recently. Until any run has returned, the
    /// `last_known_*` fallback can already be seconds old, so a first-ever run
    /// against an already-running node can still report ≈0 — the pre-split
    /// behavior, self-correcting once a result lands. The delta itself is
    /// computed once and feeds both the named field and the sentence, so the
    /// two can never report different numbers.
    ///
    /// Nothing is persisted here: the reading becomes a recorded tip only when
    /// the run's result is actually returned — a run cancelled or stopped
    /// between the last question and that return reports nothing, so it must
    /// not advance a baseline it never reported. The actions make that call
    /// through `persistReportedTip(from:to:)` on their `.result` path.
    private static func measuredReport(
        outcome: NodeAutomation.Outcome,
        previous: NodeAutomation.TipBaseline?,
        reading: NodeAutomation.LiveReading,
        session: NodeSession,
        onProgress: @MainActor (Double) -> Void
    ) async -> NodeRunReport {
        let blocksSinceLastCheck = NodeAutomation.blocksSince(previous: previous, to: reading)
        let connections = await connectionCount(session: session)
        // The peer-count question above is another bounded wait — the same window
        // every path in this file re-checks after. A node stopped in those last
        // seconds, or a run cancelled there, must not be reported as running.
        guard answerIsStillWanted(session: session) else { return noAnswerReport() }
        onProgress(1)
        return NodeRunReport(
            outcome: NodeRunOutcome(outcome),
            // Until the watch exists, a measured run's sync answer is
            // notMeasured and nothing is counted — on budgeted runs the gate
            // and the watch bring their own (T011, T022); the short action
            // keeps this answer permanently.
            syncResult: .notMeasured,
            chain: reading.chain,
            blockHeight: reading.height,
            blocksBehind: reading.blocksBehind,
            blocksSinceLastCheck: blocksSinceLastCheck,
            blocksGainedThisRun: nil,
            connections: connections,
            dialogTemplate: NodeAutomation.summary(
                outcome: outcome, chain: reading.chain, height: reading.height,
                blocksBehind: reading.blocksBehind, blocksSinceLastCheck: blocksSinceLastCheck,
                declinedReason: nil))
    }

    /// The report for a run that waited and the node never came up. The node is
    /// deliberately left running: it finishes coming up on its own thread and the
    /// next run sees the result. Asking a node still inside its own start-up to
    /// stop cannot be serviced and would hang until the system killed the run,
    /// which a person sees as a timeout.
    private static func didNotComeUpReport() -> NodeRunReport {
        return NodeRunReport(
            outcome: .didNotComeUp,
            syncResult: .notMeasured,
            chain: nil,
            blockHeight: nil,
            blocksGainedThisRun: nil,
            dialogTemplate: NodeAutomation.summary(
                outcome: .didNotComeUp, chain: "unknown",
                height: 0, blocksBehind: nil,
                blocksSinceLastCheck: nil, declinedReason: nil))
    }

    /// The report for a run that got no usable answer from the node — and carries no
    /// readings, because none were measured. Absent fields are how the report says
    /// "not measured"; a last-known figure beside that claim would contradict it.
    ///
    /// "No usable answer" covers a node that says it is running but never answered,
    /// and an answer that arrived only after the node was stopped or the run ended —
    /// real, but no longer describing the world, so it is discarded rather than
    /// reported.
    ///
    /// Not private — the iOS 27 action uses it as the answer of last resort when its
    /// own work ends without producing a report at all.
    static func noAnswerReport() -> NodeRunReport {
        return NodeRunReport(
            outcome: .noAnswer, syncResult: .notMeasured,
            chain: nil, blockHeight: nil, blocksGainedThisRun: nil,
            dialogTemplate: NodeAutomation.summary(
                outcome: .noAnswer, chain: "unknown", height: 0,
                blocksBehind: nil, blocksSinceLastCheck: nil,
                declinedReason: nil))
    }

    /// The node's peer count, or `nil` if it could not be asked. Absent rather than
    /// zero: a run that gained nothing because it never found a peer would otherwise
    /// look identical to one that had peers and still gained nothing.
    private static func connectionCount(session: NodeSession) async -> Int? {
        let reader = session.reader
        let info = try? await withHardTimeout(questionBudget) {
            try await reader.networkInfo()
        }
        guard let info else { return nil }
        return info.connections
    }

    /// Reads the two facts `NodeAutomation.answerIsStillWanted` weighs, at the
    /// instant it is called — which is the point of the exercise, since both can
    /// change while a question is in flight. The decision stays in
    /// `NodeAutomation`; this only gathers what it decides on.
    private static func answerIsStillWanted(session: NodeSession) -> Bool {
        NodeAutomation.answerIsStillWanted(
            runWasCancelled: Task.isCancelled,
            nodeIsStopped: session.node.nodeState.isStoppedOrStopping)
    }

    /// The last tip a run actually reported, as a `TipBaseline` — the chain and
    /// height `blocksSince` measures against. Reads the run-owned baseline —
    /// the observational `last_known_*` the sync poll writes is a different
    /// store, so a run's delta is never truncated by background polling.
    ///
    /// A baseline keeps only the two facts a delta measures — the store
    /// remembers a third (when the tip was written) that `blocksSince` has no
    /// use for. It is not a `LiveReading`, so watch-only fields
    /// (`isInitialBlockDownload`, `headers`, `tipTime`) can never be read back
    /// as if they had been measured.
    ///
    /// The observational store is the fallback for the one case where no run
    /// baseline exists yet: the first run after the split was introduced (or
    /// a fresh install's first-ever run before any poll wrote — `nil` either
    /// way then). For it, `last_known_*` is still the last tip the person was
    /// ever shown, and measuring against it preserves the delta rather than
    /// dropping the sentence. Once any run returns a result, `last_run_*`
    /// exists and the fallback is never consulted again.
    ///
    /// A chain switch reads the same way: `last_run_*` still names the old
    /// chain, `blocksSince` refuses the cross-chain subtraction, and the
    /// first run on the new chain reports no delta rather than a nonsense
    /// one — then its returned result seeds the baseline going forward. The
    /// old single store behaved this way only by timing luck: it produced a
    /// figure only once a poll the person never saw had already overwritten
    /// the old-chain tip.
    private static func lastRunBaseline() -> NodeAutomation.TipBaseline? {
        (NodeViewModel.lastRun() ?? NodeViewModel.lastKnown()).map {
            NodeAutomation.TipBaseline(chain: $0.chain, height: $0.height)
        }
    }

    /// Records the report's reading as both baselines it feeds: the run-owned
    /// `last_run_*` the next run's "blocks since last check" is measured from,
    /// and the observational `last_known_*` the dashboard's "last validated"
    /// line reads — a returned report is a legitimate observation too, though
    /// never a rewind: a same-chain `last_known_*` already ahead of the report
    /// (the poll can answer mid-question) survives.
    ///
    /// Called by the actions, not by the run itself, and only on the path that
    /// returns the report as a result. The report carries height and chain
    /// only when a measurement actually happened — a declined, unanswered, or
    /// discarded run has neither — so the guard is the whole contract: a run
    /// that reported no measurement cannot advance either baseline. Not
    /// private — both intents call it. `to` exists so tests can hand a
    /// throwaway store rather than the app's real settings.
    static func persistReportedTip(
        from report: NodeRunReport, to defaults: UserDefaults = .standard
    ) {
        guard let height = report.blockHeight, let chain = report.chain else { return }
        // `last_run_*` records exactly what this run reported — unconditional,
        // a reorg's lower tip included.
        NodeViewModel.persistLastRun(height: height, chain: chain, in: defaults)
        // The observational store may already hold a newer reading — the poll
        // can have written one while the run asked its last question. A
        // returned run must not rewind "last validated" past that: skip the
        // write when the stored tip is already ahead on the same chain. The
        // poll's unguarded writes keep reorgs and fresh heights converging on
        // their own cadence either way.
        if let known = NodeViewModel.lastKnown(in: defaults),
            known.chain == chain, known.height > height {
            return
        }
        NodeViewModel.persistLastKnown(height: height, chain: chain, in: defaults)
    }

    private static func declined(reason: LocalizedStringResource) -> NodeRunReport {
        return NodeRunReport(
            outcome: .declined,
            // A decline today has no sync answer to give; T016's weigh-in
            // refusal declines too but reports conditionsChanged — it will
            // bring its own.
            syncResult: .notMeasured,
            chain: nil,
            blockHeight: nil,
            blocksGainedThisRun: nil,
            dialogTemplate: NodeAutomation.summary(
                outcome: .declined, chain: "unknown",
                height: 0, blocksBehind: nil, blocksSinceLastCheck: nil,
                declinedReason: reason))
    }

    // MARK: - Device conditions

    /// Reads the seven conditions `NodePreflight` weighs.
    ///
    /// Deliberately here rather than beside the decision: every line touches an Apple
    /// framework and cannot be exercised by automated checks, so it sits with its caller
    /// while the decision stays testable. Free space is read as the figure the system
    /// reports for *important* work rather than raw free bytes, and is treated as a
    /// courtesy check — it counts space the system may not reclaim in time, so a write
    /// failure must still be handled.
    private static func readConditions() async -> NodePreflight.DeviceConditions {
        // Every reading here is immediate except the network one, which this
        // path waits on — briefly. The watcher started at launch normally has
        // an answer ready, but on a background launch the run reaches this line
        // within milliseconds of that start, before the first report has had
        // time to land on the watcher's queue — and reading `current` then
        // would take "not yet reported" as "not costly", silently skipping the
        // refusals that protect the person's data allowance. The wait is
        // bounded: an earlier version suspended on the report unboundedly and
        // could hang before the run ever reached the node, and a report that
        // never comes falls back to the same not-known answer `current` gives.
        let network = (try? await withHardTimeout(.seconds(2)) {
            await NetworkCostMonitor.shared.first()
        }) ?? .unknown
        let thermal = ProcessInfo.processInfo.thermalState
        let filesReadable = UIApplication.shared.isProtectedDataAvailable
        // The folder prepare is a write, attempted only when files can be read at
        // all: before the first unlock after a restart it is doomed to fail and
        // would log a scary error on every such run — for a refusal
        // `filesNotReadable` already reports on its own.
        let chainFolderExists = filesReadable && prepareChainFolder()
        return NodePreflight.DeviceConditions(
            filesReadable: filesReadable,
            chainFolderExists: chainFolderExists,
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            networkIsMetered: network.isMetered,
            networkIsDataRestricted: network.isDataRestricted,
            overheating: thermal == .serious || thermal == .critical,
            freeDiskBytes: freeDiskBytes()
        )
    }

    /// Creates the folder the chain is written into, reporting whether it is there.
    ///
    /// Done before anything else is measured because free space is measured *on this
    /// folder*: until it exists the reading comes back unknown, which the space check
    /// deliberately treats as "do not refuse" — quietly disabling the check on a first
    /// run, the one run it was written for. Only the folder's existence is weighed;
    /// the request to keep it out of backups is best-effort inside
    /// `DaemonConfig.prepareDataDirectory` — a folder that exists but is unmarked is
    /// perfectly writable, and unattended there is nobody to notice backups growing,
    /// which is why that failure is only ever logged.
    private static func prepareChainFolder() -> Bool {
        do {
            try DaemonConfig.prepareDataDirectory(at: DaemonConfig.dataDirectory)
            return true
        } catch {
            log.error(
                "run: chain folder could not be prepared — \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    private static func freeDiskBytes() -> Int64? {
        let url = DaemonConfig.dataDirectory
        guard
            let values = try? url.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey
            ]),
            let capacity = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return capacity
    }
}

#endif
