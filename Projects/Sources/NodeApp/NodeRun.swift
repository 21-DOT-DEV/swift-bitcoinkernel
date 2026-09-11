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

    /// Runs once and reports.
    ///
    /// - Parameters:
    ///   - waitForFirstAnswer: how long to keep asking the node whether it is up. The
    ///     two actions pass different budgets: the short-run action has roughly half a
    ///     minute in total, while the iOS 27 action may run for minutes. A wait that
    ///     runs out is an expected outcome, not an error — a locked phone has been
    ///     measured taking minutes to load the block index.
    ///   - onProgress: called as the wait proceeds, with a fraction from 0 to 1. The
    ///     iOS 27 action forwards this to its progress display; advancing it is also
    ///     what keeps that longer time window open.
    static func perform(
        session: NodeSession = .shared,
        waitForFirstAnswer: Duration,
        onProgress: (Double) -> Void = { _ in }
    ) async -> NodeRunReport {
        // Idempotent, and belt-and-braces: the watcher is started at process launch, but
        // this is the one path that runs with no window, so it does not rely on that.
        NetworkCostMonitor.shared.start()

        let privacyEnabled = UserDefaults.standard.bool(forKey: "tor_enabled")
        log.notice("run: entered, privacy network enabled = \(privacyEnabled, privacy: .public)")

        // Conditions first: declining before touching the node is the cheapest possible
        // outcome, and the only one that can explain itself usefully.
        if let refusal = NodePreflight.refusal(for: readConditions()) {
            log.notice("run: declined — \(String(describing: refusal), privacy: .public)")
            return declined(reason: refusal.message)
        }

        switch NodeAutomation.step(
            nodeIsStopped: session.node.nodeState == .stopped,
            privacyEnabled: privacyEnabled,
            privacyReady: session.tor.isReady
        ) {
        case .reportExistingNode:
            // Never interrupt a node someone started themselves: read it and leave it
            // alone (ADR 0005).
            log.notice("run: a node is already running — reading and leaving it alone")
            return await report(
                outcome: .alreadyRunning, session: session, onProgress: onProgress)

        case .waitForPrivateNetwork:
            // Spend the run establishing the private network rather than starting on a
            // direct connection, which would expose the person's home network address
            // after they asked it not to.
            log.notice("run: private network not ready — starting it, not starting the node")
            session.tor.start()
            return declined(
                reason:
                    "The private network was not ready, so the node did not start. It is being established now; try again shortly."
            )

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
        onProgress: (Double) -> Void
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
            // on a direct connection.
            log.error("run: refused to start without the private network")
            return declined(
                reason: "The private network was not ready, so the node did not start.")
        }

        // The height recorded before this run, so the report can say what arrived since
        // — which spans the minutes the node kept running after an earlier run ended.
        let previous = NodeViewModel.lastKnown.map {
            NodeAutomation.LiveReading(chain: $0.chain, height: $0.height, blocksBehind: 0)
        }

        session.node.start(
            arguments: arguments,
            torSession: privacyEnabled ? session.tor.sessionID : nil,
            torSocksPort: privacyEnabled
                ? session.tor.socksEndpoint.map { UInt16(clamping: $0.port) } : nil
        )
        log.notice("run: node start requested")

        guard
            let reading = await awaitFirstAnswer(
                session: session, within: waitForFirstAnswer, onProgress: onProgress)
        else {
            // Deliberately left running. It finishes coming up on its own thread, and
            // the next run will see the result. Asking a node still inside its own
            // start-up to stop cannot be serviced and would hang until the system
            // killed the run, which a person sees as a timeout.
            log.notice("run: node had not come up within the time available — left running")
            return NodeRunReport(
                outcome: .didNotComeUp,
                chain: previous?.chain ?? "unknown",
                blockHeight: previous?.height ?? 0,
                summary: NodeAutomation.summary(
                    outcome: .didNotComeUp, chain: previous?.chain ?? "unknown",
                    height: previous?.height ?? 0, blocksBehind: nil,
                    blocksSinceLastCheck: nil, declinedReason: nil))
        }

        log.notice("run: node answered at block \(reading.height, privacy: .public)")
        NodeViewModel.persistLastKnown(height: reading.height, chain: reading.chain)

        // Computed once and used for both the named field and the sentence, so the two
        // can never report different numbers.
        let gained = NodeAutomation.blocksGained(from: previous, to: reading)
        return NodeRunReport(
            outcome: .started,
            chain: reading.chain,
            blockHeight: reading.height,
            blocksBehind: reading.blocksBehind,
            blocksSinceLastCheck: gained,
            connections: await connectionCount(session: session),
            summary: NodeAutomation.summary(
                outcome: .started, chain: reading.chain, height: reading.height,
                blocksBehind: reading.blocksBehind, blocksSinceLastCheck: gained,
                declinedReason: nil))
    }

    /// Keeps asking the node whether it is up, giving up at the deadline.
    ///
    /// Asks the node directly rather than watching the app's own "running" flag, which
    /// is set by a start-up loop that backs off to two-second gaps — up to two seconds
    /// of a short run would otherwise be spent with the node already up and nobody
    /// looking. Asking directly also yields the height without a second round trip.
    ///
    /// One deadline is computed up front rather than accumulating intervals, state is
    /// re-read every time rather than assumed (someone may open the app and stop the
    /// node mid-wait), and the sleep is interruptible so a stopped run exits promptly.
    private static func awaitFirstAnswer(
        session: NodeSession,
        within budget: Duration,
        onProgress: (Double) -> Void
    ) async -> NodeAutomation.LiveReading? {
        let started = ContinuousClock.now
        let deadline = started.advanced(by: budget)
        let budgetSeconds = Double(budget / .milliseconds(1)) / 1000

        while ContinuousClock.now < deadline {
            if Task.isCancelled { return nil }
            if session.node.nodeState == .stopped { return nil }
            if let info = try? await session.reader.blockchainInfo() {
                // Re-read both facts now the answer is actually here, rather than
                // trusting the check at the top of this pass. A question already in
                // flight cannot be called back, so its answer can land after the run
                // was stopped or after someone opened the app and shut the node down.
                // Reporting it then would claim a success contradicting what they just
                // did. The decision itself lives in `NodeAutomation` and is tested.
                guard
                    NodeAutomation.answerIsStillWanted(
                        runWasCancelled: Task.isCancelled,
                        nodeIsStopped: session.node.nodeState == .stopped)
                else { return nil }
                onProgress(1)
                return NodeAutomation.reading(from: info)
            }
            let elapsed = Double(started.duration(to: .now) / .milliseconds(1)) / 1000
            onProgress(budgetSeconds > 0 ? min(0.99, elapsed / budgetSeconds) : 0)
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return nil }
        }
        return nil
    }

    // MARK: - Reading

    /// Reads a node that is already up.
    ///
    /// Takes `onProgress` for the same reason the waiting loop does. This path used to
    /// report nothing at all, so an extended run spent the whole read showing an empty
    /// bar and then jumped to full — the exact shape the action was written to avoid.
    /// It matters beyond appearances: the channel used to ask the node a question waits
    /// up to thirty seconds for an answer, and roughly thirty seconds without a
    /// progress report is what it takes for the system to decide an extended run has
    /// stalled and end it. So a single slow question here could have the run killed.
    ///
    /// The repeating nudge in the action is what actually guarantees the run keeps
    /// reporting; these milestones exist so the movement corresponds to something real
    /// rather than being pure invention.
    private static func report(
        outcome: NodeAutomation.Outcome,
        session: NodeSession,
        onProgress: (Double) -> Void
    ) async -> NodeRunReport {
        onProgress(0.1)
        guard let info = try? await session.reader.blockchainInfo() else {
            // It says it is running but will not answer.
            return noAnswerReport()
        }
        onProgress(0.6)
        let reading = NodeAutomation.reading(from: info)
        let previous = NodeViewModel.lastKnown.map {
            NodeAutomation.LiveReading(chain: $0.chain, height: $0.height, blocksBehind: 0)
        }
        NodeViewModel.persistLastKnown(height: reading.height, chain: reading.chain)
        let gained = NodeAutomation.blocksGained(from: previous, to: reading)
        let connections = await connectionCount(session: session)
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

    /// The report for a node that would not answer: the last height this app recorded,
    /// rather than an invented one.
    ///
    /// Not private — the action uses it as the answer of last resort when its own work
    /// ends without producing a report at all.
    static func noAnswerReport() -> NodeRunReport {
        let saved = NodeViewModel.lastKnown
        return NodeRunReport(
            outcome: .didNotComeUp, chain: saved?.chain ?? "unknown",
            blockHeight: saved?.height ?? 0,
            summary: NodeAutomation.summary(
                outcome: .didNotComeUp, chain: saved?.chain ?? "unknown",
                height: saved?.height ?? 0, blocksBehind: nil, blocksSinceLastCheck: nil,
                declinedReason: nil))
    }

    /// The node's peer count, or `nil` if it could not be asked. Absent rather than
    /// zero: a run that gained nothing because it never found a peer would otherwise
    /// look identical to one that had peers and still gained nothing.
    private static func connectionCount(session: NodeSession) async -> Int? {
        guard let info = try? await session.reader.networkInfo() else { return nil }
        return info.connections
    }

    private static func declined(reason: String) -> NodeRunReport {
        let saved = NodeViewModel.lastKnown
        return NodeRunReport(
            outcome: .declined,
            chain: saved?.chain ?? "unknown",
            blockHeight: saved?.height ?? 0,
            summary: NodeAutomation.summary(
                outcome: .declined, chain: saved?.chain ?? "unknown",
                height: saved?.height ?? 0, blocksBehind: nil, blocksSinceLastCheck: nil,
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
    private static func readConditions() -> NodePreflight.DeviceConditions {
        // Every reading here is immediate. The network answer comes from a watcher that
        // has been running since app launch, so nothing waits: an earlier version
        // suspended here waiting for a network report and could hang before the run
        // ever reached the node.
        let network = NetworkCostMonitor.shared.current
        let thermal = ProcessInfo.processInfo.thermalState
        return NodePreflight.DeviceConditions(
            filesReadable: UIApplication.shared.isProtectedDataAvailable,
            storagePrepared: prepareStorage(),
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            networkIsMetered: network.isMetered,
            networkIsDataRestricted: network.isDataRestricted,
            overheating: thermal == .serious || thermal == .critical,
            freeDiskBytes: freeDiskBytes()
        )
    }

    /// Creates the folder the chain is written into and marks it so the system does not
    /// copy it into backups, reporting whether that worked.
    ///
    /// Done here, before anything else is measured, for two reasons. A failure means
    /// either there is nowhere to write or gigabytes of chain data would be swept into
    /// the person's backups — and unattended there is nobody to notice, so the run has
    /// to refuse rather than carry on. And free space is measured *on this folder*, so
    /// until it exists the reading comes back unknown, which the space check
    /// deliberately treats as "do not refuse" — quietly disabling the check on a first
    /// run, the one run it was written for.
    private static func prepareStorage() -> Bool {
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
