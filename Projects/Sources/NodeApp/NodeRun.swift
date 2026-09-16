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
    ///     is also what keeps that longer time window open.
    static func perform(
        session: NodeSession,
        waitForFirstAnswer: Duration,
        onProgress: @MainActor (Double) -> Void = { _ in }
    ) async -> NodeRunReport {
        let privacyEnabled = UserDefaults.standard.bool(forKey: "tor_enabled")
        log.notice("run: entered, privacy network enabled = \(privacyEnabled, privacy: .public)")

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
            privacyEnabled: privacyEnabled,
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
            // Spend the run establishing the private network rather than starting on a
            // direct connection, which would expose the person's home network address
            // after they asked it not to.
            log.notice("run: private network not ready — starting it, not starting the node")
            session.tor.start()
            return declined(
                reason: NodeAutomation.StartRefusal.privateNetworkNotReady.message)

        case .startNode:
            return await start(
                session: session, privacyEnabled: privacyEnabled,
                waitForFirstAnswer: waitForFirstAnswer, onProgress: onProgress)
        }
    }

    // MARK: - Starting

    private static func start(
        session: NodeSession,
        privacyEnabled: Bool,
        waitForFirstAnswer: Duration,
        onProgress: @MainActor (Double) -> Void
    ) async -> NodeRunReport {
        let argumentsOrRefusal = Result {
            try NodeAutomation.startArguments(
                privacyEnabled: privacyEnabled,
                proxyAddress: session.tor.proxyAddress,
                build: { DaemonConfig.buildArguments(torProxy: $0) })
        }
        guard case let .success(arguments) = argumentsOrRefusal else {
            // The guard exists because the shared argument builder simply omits the
            // proxy when no address is present, which unattended would start the node
            // on a direct connection. It is live rather than vestigial: the
            // device-condition read suspends on the first network report, and the
            // private network can drop in that window — after the step decision has
            // already committed to starting. (While that read could not suspend,
            // the guard genuinely was unreachable.) If reached, nudge the network
            // back up (a no-op while a retry is already pending) and decline with
            // the same sentence the deliberate wait-for-it path uses.
            log.error("run: refused to start without the private network")
            session.tor.start()
            return declined(
                reason: NodeAutomation.StartRefusal.privateNetworkNotReady.message)
        }

        // The height recorded before this run, so the report can say what arrived since
        // — which spans the minutes the node kept running after an earlier run ended.
        // Captured before the wait, not after: once the node reaches `.running` its
        // own sync poll begins overwriting it.
        let previous = lastKnownReading()

        // The last checkpoint before the side effect: the condition read and the
        // argument build suspend nowhere, but a run cancelled in that window would
        // still launch the node it was called off to prevent.
        guard !Task.isCancelled else { return noAnswerReport() }

        session.node.start(
            arguments: arguments,
            torSession: privacyEnabled ? session.tor.sessionID : nil,
            torSocksPort: privacyEnabled
                ? session.tor.socksEndpoint.flatMap { UInt16(exactly: $0.port) } : nil
        )
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
        // the node reaches `.running` its own sync poll overwrites it.
        let previous = lastKnownReading()
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
            outcome: .alreadyRunning, previous: lastKnownReading(),
            reading: NodeAutomation.reading(from: info),
            session: session, onProgress: onProgress)
    }

    /// The report for a run holding a real reading: persists the tip, asks the
    /// last question (the peer count, bounded like every other), and fills the
    /// bar only once nothing is still outstanding.
    ///
    /// `previous` is captured by the caller before its wait rather than read here,
    /// because once a node reaches `.running` its own sync poll starts persisting
    /// newer heights — a snapshot taken after the wait could be one this run's
    /// own node just wrote, shrinking the "blocks since last check" delta toward
    /// zero. The delta itself is computed once and feeds both the named field and
    /// the sentence, so the two can never report different numbers.
    private static func measuredReport(
        outcome: NodeAutomation.Outcome,
        previous: NodeAutomation.LiveReading?,
        reading: NodeAutomation.LiveReading,
        session: NodeSession,
        onProgress: @MainActor (Double) -> Void
    ) async -> NodeRunReport {
        NodeViewModel.persistLastKnown(height: reading.height, chain: reading.chain)
        let gained = NodeAutomation.blocksGained(from: previous, to: reading)
        let connections = await connectionCount(session: session)
        // The peer-count question above is another bounded wait — the same window
        // every path in this file re-checks after. A node stopped in those last
        // seconds, or a run cancelled there, must not be reported as running.
        guard answerIsStillWanted(session: session) else { return noAnswerReport() }
        onProgress(1)
        return NodeRunReport(
            outcome: NodeRunOutcome(outcome),
            chain: reading.chain,
            blockHeight: reading.height,
            blocksBehind: reading.blocksBehind,
            blocksSinceLastCheck: gained,
            connections: connections,
            summary: NodeAutomation.summary(
                outcome: outcome, chain: reading.chain, height: reading.height,
                blocksBehind: reading.blocksBehind, blocksSinceLastCheck: gained,
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
            chain: nil,
            blockHeight: nil,
            summary: NodeAutomation.summary(
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
            outcome: .noAnswer, chain: nil, blockHeight: nil,
            summary: NodeAutomation.summary(
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

    /// The last tip anyone recorded, as a `LiveReading` so it can feed the
    /// blocks-gained calculation.
    private static func lastKnownReading() -> NodeAutomation.LiveReading? {
        NodeViewModel.lastKnown.map {
            NodeAutomation.LiveReading(chain: $0.chain, height: $0.height, blocksBehind: 0)
        }
    }

    private static func declined(reason: String) -> NodeRunReport {
        return NodeRunReport(
            outcome: .declined,
            chain: nil,
            blockHeight: nil,
            summary: NodeAutomation.summary(
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
