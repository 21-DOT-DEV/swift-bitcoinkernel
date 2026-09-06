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
import Bitcoin
import Foundation
import os.log

// Phone and tablet only. A home automation runs from a home hub — a HomePod, Apple
// TV, or iPad — and never from a Mac, so this feature's purpose is unreachable there.
// See Development/Specs/003-node-automation-action/plan.md §2.
//
// Excluded at compile time rather than by an availability annotation: an annotation
// still compiles the file on macOS and only refuses it at runtime, which would ship
// the action's code into a build that must never offer it. `os(iOS)` covers both
// iPhone and iPad.
#if os(iOS)

// UIKit only for the background-task assertion below; the rest of this file is
// framework-agnostic. Imported inside the guard because macOS has no UIKit.
import UIKit

/// Everything this action reports to the system log, under one category so it can be
/// filtered to on its own.
///
/// Written at `notice` level rather than `debug` on purpose: debug messages are held
/// in memory only and are gone by the time anyone reads the log after a failed
/// automation. Values are marked public explicitly, because dynamic values are
/// redacted by default and a log full of `<private>` answers nothing.
///
/// Subsystem and category follow what the app already uses elsewhere — the app's
/// identifier, then a word naming the area.
enum RunLog {
    static let logger = Logger(subsystem: "dev.21.NodeApp", category: "Shortcut")

    static func entered(privacyEnabled: Bool) {
        logger.notice("run: entered, privacy network enabled = \(privacyEnabled, privacy: .public)")
    }

    static func decided(_ step: String) {
        logger.notice("run: step = \(step, privacy: .public)")
    }

    static func mark(_ event: String, msSinceStart: Int) {
        logger.notice("run: \(event, privacy: .public) at \(msSinceStart, privacy: .public) ms")
    }

    static func interrupted(msSinceStart: Int) {
        // The reason the run ended, which the failure notice never says.
        logger.notice("run: INTERRUPTED by the system at \(msSinceStart, privacy: .public) ms")
    }

    static func finished(outcome: String, height: Int, msSinceStart: Int) {
        logger.notice(
            "run: finished \(outcome, privacy: .public), height \(height, privacy: .public), total \(msSinceStart, privacy: .public) ms")
    }

    static func failed(_ reason: String, msSinceStart: Int) {
        logger.error("run: FAILED \(reason, privacy: .public) at \(msSinceStart, privacy: .public) ms")
    }
}

/// What an unattended run did.
enum NodeRunOutcome: String, AppEnum {
    case startedAndRan
    case alreadyRunning
    case waitingOnPrivateNetwork
    case couldNotStart

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Node Run Outcome" }

    static var caseDisplayRepresentations: [NodeRunOutcome: DisplayRepresentation] {
        [.startedAndRan: "Started and ran",
         .alreadyRunning: "Already running",
         .waitingOnPrivateNetwork: "Waiting on private network",
         .couldNotStart: "Could not start"]
    }
}

/// What the action hands back.
///
/// Four named fields, each usable as its own variable in the next step of someone's
/// automation. Height alone misleads: a node tracks both the height it has fully
/// validated and the headers it knows about, and during catch-up the second runs far
/// ahead of the first, so a height with no remaining-blocks figure reads as "caught
/// up" when it is not.
///
/// These names are a commitment — renaming or removing one silently breaks
/// automations people have already built.
struct NodeRunReport: TransientAppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Node Run Report" }

    @Property(title: "Outcome") var outcome: NodeRunOutcome
    /// Which chain the height belongs to. A height means nothing without it.
    @Property(title: "Chain") var chain: String
    @Property(title: "Block height") var blockHeight: Int
    @Property(title: "Blocks behind") var blocksBehind: Int
    /// Minutes since the height was recorded, when it came from saved data rather
    /// than a live reading. Absent means the figure is live.
    @Property(title: "Height age in minutes") var heightAgeMinutes: Int?
    /// How long the node was genuinely running. Startup produces no blocks, so this
    /// is the only interval in which the height could have moved.
    @Property(title: "Seconds running") var secondsRunning: Double
    /// Blocks gained during this run, measured at both ends rather than inferred by
    /// comparing against the previous run. Absent when it could not be measured.
    @Property(title: "Blocks gained") var blocksGained: Int?
    /// Connections the node had when the run ended. A run that gained nothing with
    /// zero connections is explained; one with peers is a different problem.
    @Property(title: "Connections") var connections: Int?

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(summary)") }

    var summary: String {
        switch outcome {
        case .startedAndRan:
            let ran = String(format: "%.1f", secondsRunning)
            let gained = NodeAutomation.gainPhrase(blocksGained)
            let behind = blocksBehind > 0 ? ", \(blocksBehind) behind" : ""
            // Nothing gained with nobody to gain it from is a different problem from
            // nothing gained despite peers, and only the report can tell them apart.
            let peers = (blocksGained == 0 && connections == 0) ? " No connections." : ""
            return "Ran \(ran)s on \(chain): \(gained), now at \(blockHeight)\(behind).\(peers)"
        case .alreadyRunning:
            return "Already running; left alone. Height \(blockHeight) on \(chain)\(ageSuffix)."
        case .waitingOnPrivateNetwork:
            return "Spent the run establishing the private network; the node did not start."
        case .couldNotStart:
            return "The node did not come up in time; nothing was synced."
        }
    }

    private var ageSuffix: String {
        guard let heightAgeMinutes else { return "" }
        return " (recorded \(heightAgeMinutes) minutes ago)"
    }

    init() {}

    init(outcome: NodeRunOutcome, chain: String, blockHeight: Int, blocksBehind: Int,
         heightAgeMinutes: Int?, secondsRunning: Double,
         blocksGained: Int? = nil, connections: Int? = nil) {
        self.init()
        self.outcome = outcome
        self.chain = chain
        self.blockHeight = blockHeight
        self.blocksBehind = blocksBehind
        self.heightAgeMinutes = heightAgeMinutes
        self.secondsRunning = secondsRunning
        self.blocksGained = blocksGained
        self.connections = connections
    }
}

/// Holds the system's "do not suspend this app" assertion for the length of a run.
///
/// The log showed the app raising none at all, which lets the system freeze it partway
/// through. For a Bitcoin node that means the data directory stays locked and the next
/// run cannot start. The expiry callback is a backstop only: it is given a couple of
/// seconds and a clean shutdown has been measured at up to 4.8, so shutting down must
/// already be underway by then rather than starting there.
@MainActor
final class BackgroundAssertion {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(name: String, onExpiry: @escaping @MainActor () -> Void) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // Documented to be called on the main thread. Asserting that rather than
            // hopping to it: a hop would land after the system has already killed us.
            MainActor.assumeIsolated {
                onExpiry()
                self?.end()
            }
        }
    }

    /// Deliberately safe to call twice, because both the normal path and the expiry
    /// callback end it and either can come first. Not ending it at all, or ending it
    /// twice, both get the app killed.
    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

/// Starts the node unattended, lets it run for the window the system allows, shuts it
/// down cleanly, and reports what happened.
struct SyncNodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Sync Bitcoin Node"
    static let description = IntentDescription(
        """
        Starts the node, lets it sync for as long as a background action is allowed, \
        then shuts it down and reports the block height reached. Leaves a node you \
        started yourself alone. If you route through the private network, this needs \
        to run more often than its cached directory data goes stale — a few hours — \
        or every run will spend its time re-establishing the connection.
        """)
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<NodeRunReport> & ProvidesDialog {
        let started = ContinuousClock.now
        let deadline = NodeAutomation.workDeadline(from: started)
        func ms() -> Int { Int(started.duration(to: .now) / .milliseconds(1)) }

        let assertion = BackgroundAssertion(name: "Sync Bitcoin Node") {
            RunLog.mark("system expiry callback fired", msSinceStart: ms())
        }
        defer { assertion.end() }

        // Reports before the privacy gate below, so a refusal still reaches someone.
        // On an unattended run the dialog this action returns has nowhere to be
        // displayed — nobody is watching a 3am automation — so this is the only
        // evidence the run happened (ADR 0006).
        let reporter: any RunReporter = NotificationReporter()

        let session = NodeSession.shared
        let privacyEnabled = UserDefaults.standard.bool(forKey: "tor_enabled")
        RunLog.entered(privacyEnabled: privacyEnabled)

        switch NodeAutomation.step(
            nodeIsStopped: session.node.nodeState == .stopped,
            privacyEnabled: privacyEnabled,
            privacyReady: session.tor.isReady
        ) {
        case .reportExistingNode:
            RunLog.decided("reportExistingNode")
            let existing = Self.savedReport(outcome: .alreadyRunning)
            await reporter.finish(.adopted(height: existing.blockHeight))
            return Self.finish(existing, ms: ms())

        case .waitForPrivateNetwork:
            RunLog.decided("waitForPrivateNetwork")
            session.tor.start()
            RunLog.mark("privacy network start requested", msSinceStart: ms())
            await Self.holdUntil(deadline, log: { RunLog.interrupted(msSinceStart: ms()) })
            RunLog.mark("privacy network ready = \(session.tor.isReady)", msSinceStart: ms())
            await reporter.finish(.refusedPrivateNetworkUnavailable)
            return Self.finish(Self.savedReport(outcome: .waitingOnPrivateNetwork), ms: ms())

        case .startNode:
            RunLog.decided("startNode")
            // Checked and set together, so two runs triggered close together cannot
            // both believe they own the node.
            guard session.claimForAutomation() else {
                RunLog.failed("another unattended run already holds the session", msSinceStart: ms())
                return Self.finish(Self.savedReport(outcome: .alreadyRunning), ms: ms())
            }
            defer { session.releaseAutomation() }

            let arguments: [String]
            do {
                arguments = try NodeAutomation.startArguments(
                    privacyEnabled: privacyEnabled,
                    proxyAddress: session.tor.proxyAddress,
                    build: { DaemonConfig.buildArguments(torProxy: $0) }
                )
            } catch {
                // ADR 0006: never start on a direct connection.
                RunLog.failed("refused to start without the private network", msSinceStart: ms())
                await reporter.finish(.refusedPrivateNetworkUnavailable)
                return Self.finish(Self.savedReport(outcome: .waitingOnPrivateNetwork), ms: ms())
            }

            let socksPort = privacyEnabled
                ? session.tor.socksEndpoint.map { UInt16(clamping: $0.port) }
                : nil
            session.node.start(
                arguments: arguments,
                torSession: privacyEnabled ? session.tor.sessionID : nil,
                torSocksPort: socksPort
            )
            RunLog.mark("node start requested", msSinceStart: ms())

            // Wait until the node answers, re-checking, giving up at the deadline.
            // Not a fixed wait: a length chosen so one thing finishes before another
            // reports how busy the machine is, not whether the code works (ADR 0007
            // and its sibling in the other project).
            guard let ready = await Self.waitUntilAnswering(session: session, deadline: deadline) else {
                RunLog.failed("node never reported ready before the deadline", msSinceStart: ms())
                await reporter.finish(.failed(reason: "it did not come up in time"))
                await Self.shutDown(session: session, ms: ms)
                return Self.finish(Self.savedReport(outcome: .couldNotStart), ms: ms())
            }
            let baseline = ready.reading
            RunLog.mark("node READY at height \(baseline.height)", msSinceStart: ms())

            await Self.holdUntil(deadline, log: { RunLog.interrupted(msSinceStart: ms()) })
            let stoppedAt = ContinuousClock.now
            let running = NodeAutomation.secondsRunning(readyAt: ready.at, stoppedAt: stoppedAt)
            RunLog.mark("hold ended after \(String(format: "%.1f", running))s running", msSinceStart: ms())

            // Read while the node is still up: after shutdown there is nothing to ask.
            let live = await Self.readLive(session: session, ms: ms)
            let peers = await Self.readConnections(session: session, ms: ms)
            RunLog.mark("connections = \(peers.map(String.init) ?? "unknown")", msSinceStart: ms())

            // Reported before the shutdown wait rather than after. The wait cannot be
            // interrupted and has run to 5.1 s, so a run killed inside it would
            // otherwise report nothing at all. The height cannot be re-read after
            // shutdown either way, so nothing is lost by reporting early.
            await reporter.finish(.completed(
                height: live?.height ?? Self.savedReport(outcome: .startedAndRan).blockHeight,
                blocksGained: NodeAutomation.blocksGained(from: baseline, to: live),
                connections: peers
            ))

            let shutdownBegan = ContinuousClock.now
            await Self.shutDown(session: session, ms: ms)
            let shutdownTook = shutdownBegan.duration(to: .now)
            if NodeAutomation.shutdownOverran(shutdownTook) {
                RunLog.mark(
                    "shutdown OVERRAN its reserve: took \(shutdownTook), held back \(NodeAutomation.shutdownReserve)",
                    msSinceStart: ms())
            }

            guard let live else {
                let report = Self.savedReport(outcome: .startedAndRan)
                report.secondsRunning = running
                report.connections = peers
                return Self.finish(report, ms: ms())
            }
            let report = NodeRunReport(
                outcome: .startedAndRan, chain: live.chain, blockHeight: live.height,
                blocksBehind: live.blocksBehind, heightAgeMinutes: nil, secondsRunning: running,
                blocksGained: NodeAutomation.blocksGained(from: baseline, to: live),
                connections: peers
            )
            return Self.finish(report, ms: ms())
        }
    }

    /// Waits until the node answers a question, re-checking at intervals and giving
    /// up at `deadline`. Returns when it first answered and the height it reported.
    ///
    /// Asks the node directly rather than waiting for the app's own "running" flag.
    /// The flag is set by a start-up loop that backs off to two-second gaps, so up to
    /// two seconds of a run were spent with the node already up and nobody looking.
    /// Out of a usable twenty-one that is worth reclaiming, and asking directly also
    /// yields the starting height without a second round trip.
    ///
    /// State is re-read every time rather than assumed, because other work can run in
    /// between — someone opening the app and stopping the node, for instance.
    @MainActor
    private static func waitUntilAnswering(
        session: NodeSession, deadline: ContinuousClock.Instant
    ) async -> (at: ContinuousClock.Instant, reading: NodeAutomation.LiveReading)? {
        while ContinuousClock.now < deadline {
            if session.node.nodeState == .stopped { return nil }
            if let info = try? await session.reader.blockchainInfo() {
                return (ContinuousClock.now, NodeAutomation.reading(from: info))
            }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return nil }
        }
        return nil
    }

    /// The node's connection count, or nil if it could not be read.
    ///
    /// Explains an otherwise baffling report: a run that gains no blocks because it
    /// never found a peer looks identical to one that had peers and still gained
    /// nothing, and only the first is expected on a short unattended run.
    @MainActor
    private static func readConnections(session: NodeSession, ms: () -> Int) async -> Int? {
        guard let info = try? await session.reader.networkInfo() else {
            RunLog.mark("connection count unavailable", msSinceStart: ms())
            return nil
        }
        return info.connections
    }

    /// Holds until the deadline, or until the system stops the run — whichever first.
    ///
    /// The interruption is caught rather than discarded. Writing `try?` here meant a
    /// stopped run returned instantly and was then reported as a success.
    private static func holdUntil(
        _ deadline: ContinuousClock.Instant, log: () -> Void
    ) async {
        do { try await Task.sleep(until: deadline, clock: .continuous) } catch { log() }
    }

    @MainActor
    private static func readLive(
        session: NodeSession, ms: () -> Int
    ) async -> NodeAutomation.LiveReading? {
        do {
            return NodeAutomation.reading(from: try await session.reader.blockchainInfo())
        } catch {
            RunLog.failed("live reading failed: \(error.localizedDescription)", msSinceStart: ms())
            return nil
        }
    }

    @MainActor
    private static func shutDown(session: NodeSession, ms: () -> Int) async {
        RunLog.mark("shutdown started", msSinceStart: ms())
        await session.node.performStop()
        RunLog.mark("shutdown finished", msSinceStart: ms())
    }

    /// Builds a report from the saved tip, since a node that is starting, stopping, or
    /// already shut down has no live figure to offer.
    @MainActor
    private static func savedReport(outcome: NodeRunOutcome) -> NodeRunReport {
        guard let last = NodeViewModel.lastKnown else {
            // Nothing has ever been recorded. Blocks-behind is -1 for "unknown" here
            // too: zero would claim the node is caught up at height zero.
            return NodeRunReport(outcome: outcome, chain: "unknown", blockHeight: 0,
                                 blocksBehind: -1, heightAgeMinutes: nil, secondsRunning: 0)
        }
        let age = Int(Date().timeIntervalSince(last.date) / 60)
        // Blocks-behind is unknown from a saved figure; it is reported as -1 rather
        // than 0, because 0 would claim the node is caught up.
        return NodeRunReport(outcome: outcome, chain: last.chain, blockHeight: last.height,
                             blocksBehind: -1, heightAgeMinutes: age, secondsRunning: 0)
    }

    private static func finish(
        _ report: NodeRunReport, ms: Int
    ) -> some IntentResult & ReturnsValue<NodeRunReport> & ProvidesDialog {
        RunLog.finished(outcome: report.outcome.rawValue, height: report.blockHeight, msSinceStart: ms)
        return .result(value: report, dialog: IntentDialog(stringLiteral: report.summary))
    }
}

/// Publishes the action so it appears in Shortcuts and can be added to a Home
/// automation. Gated by availability rather than a compile-time condition, because
/// this list accepts only platform-availability conditions.
struct NodeAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SyncNodeIntent(),
            phrases: ["Sync my node in \(.applicationName)"],
            shortTitle: "Sync Bitcoin Node",
            systemImageName: "bitcoinsign.circle"
        )
    }
}
#endif
