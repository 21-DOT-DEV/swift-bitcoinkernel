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

// Phone and tablet only, for the reason recorded in
// Development/Specs/003-node-automation-action/plan.md §2. Excluded at compile
// time rather than by an availability annotation, which would still compile this
// into a Mac build and only refuse it at runtime.
#if os(iOS)

/// Whether a shutdown has finished. A reference so the polling loop and the task
/// doing the work see the same value; both are on the main actor, so no lock.
@MainActor
private final class ShutdownProgress {
    var finished = false
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

    /// Whether to stop the node when the action finishes.
    ///
    /// Off by default, and that default is the point. The action gets about 27
    /// seconds, but the node it starts carries on for minutes afterwards, which is
    /// when it actually downloads anything. Switching this on returns the phone's
    /// resources sooner at the cost of most of what the run would have achieved.
    @Parameter(
        title: "Stop the node when finished",
        description:
            "Leave this off to let the node keep syncing in the background after the action finishes, which is when most blocks arrive. Turn it on to stop the node as soon as the action ends.",
        default: false
    )
    var stopWhenFinished: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<NodeRunReport>
        & ProvidesDialog
    {
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
        let reporter = NotificationReporter()

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
            await reporter.post(.adopted(height: existing.blockHeight))
            return Self.finish(existing, ms: ms())

        case .waitForPrivateNetwork:
            RunLog.decided("waitForPrivateNetwork")
            session.tor.start()
            RunLog.mark("privacy network start requested", msSinceStart: ms())
            await Self.holdUntil(deadline, log: { RunLog.interrupted(msSinceStart: ms()) })
            RunLog.mark("privacy network ready = \(session.tor.isReady)", msSinceStart: ms())
            await reporter.post(.refusedPrivateNetworkUnavailable)
            return Self.finish(Self.savedReport(outcome: .waitingOnPrivateNetwork), ms: ms())

        case .startNode:
            RunLog.decided("startNode")
            // Checked and set together, so two runs triggered close together cannot
            // both believe they own the node.
            guard session.claimForAutomation() else {
                RunLog.failed(
                    "another unattended run already holds the session", msSinceStart: ms())
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
                RunLog.failed(
                    "refused to start without the private network", msSinceStart: ms())
                await reporter.post(.refusedPrivateNetworkUnavailable)
                return Self.finish(
                    Self.savedReport(outcome: .waitingOnPrivateNetwork), ms: ms())
            }

            let socksPort =
                privacyEnabled
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
            guard
                let ready = await Self.waitUntilAnswering(session: session, deadline: deadline)
            else {
                RunLog.failed(
                    "node never reported ready before the deadline", msSinceStart: ms())
                await reporter.post(.failed(reason: "it did not come up in time"))
                if NodeAutomation.shouldRequestShutdown(
                    nodeAnswered: false, askedToStop: stopWhenFinished
                ) {
                    _ = await Self.shutDown(
                        session: session, within: NodeAutomation.shutdownReserve, ms: ms)
                }
                // Left running deliberately. It finishes its start-up on its own
                // thread or dies with the process; either way the run returns instead
                // of hanging until the system kills it.
                return Self.finish(Self.savedReport(outcome: .couldNotStart), ms: ms())
            }
            RunLog.mark("node READY at height \(ready.reading.height)", msSinceStart: ms())

            // Progress is measured from the last height this app recorded, not from
            // the start of this run. The run itself gains almost nothing — it is
            // about to return — while the node carries on downloading for minutes
            // after it does. Measuring from the recorded height is what captures
            // that, and it is the only figure showing the feature works at all.
            let previous = NodeViewModel.lastKnown.map {
                NodeAutomation.LiveReading(chain: $0.chain, height: $0.height, blocksBehind: 0)
            }
            let sinceLastCheck = NodeAutomation.blocksGained(from: previous, to: ready.reading)
            NodeViewModel.persistLastKnown(
                height: ready.reading.height, chain: ready.reading.chain)

            // Only wait if we were asked to stop the node afterwards. Waiting
            // otherwise buys nothing: the blocks arrive after this returns either
            // way, and lingering only pushes the run toward the system's cut-off,
            // which has already produced one visible timeout.
            var ran = 0.0
            var live: NodeAutomation.LiveReading? = nil
            var peers: Int? = nil
            if NodeAutomation.shouldRequestShutdown(
                nodeAnswered: true, askedToStop: stopWhenFinished
            ) {
                await Self.holdUntil(deadline, log: { RunLog.interrupted(msSinceStart: ms()) })
                ran = NodeAutomation.secondsRunning(readyAt: ready.at, stoppedAt: .now)
                // Read while the node is still up: after it stops there is nothing
                // left to ask.
                live = await Self.readLive(session: session, ms: ms)
                peers = await Self.readConnections(session: session, ms: ms)
                RunLog.mark(
                    "waited \(String(format: "%.1f", ran))s, connections = \(peers.map(String.init) ?? "unknown")",
                    msSinceStart: ms())
            }

            let tip = live ?? ready.reading
            await reporter.post(
                .completed(height: tip.height, blocksSinceLastCheck: sinceLastCheck))

            if NodeAutomation.shouldRequestShutdown(
                nodeAnswered: true, askedToStop: stopWhenFinished
            ) {
                let shutdownBegan = ContinuousClock.now
                _ = await Self.shutDown(
                    session: session, within: NodeAutomation.shutdownReserve, ms: ms
                )
                let took = shutdownBegan.duration(to: .now)
                if NodeAutomation.shutdownOverran(took) {
                    RunLog.mark(
                        "shutdown OVERRAN its reserve: took \(took), held back \(NodeAutomation.shutdownReserve)",
                        msSinceStart: ms())
                }
            } else {
                RunLog.mark("left the node running, as configured", msSinceStart: ms())
            }

            // The three run-specific figures stay absent unless the run actually
            // waited and measured them. Absent says "not measured"; zero would say
            // "measured, and it was nothing", and confusing those is what made the
            // earlier reporting misleading.
            let report = NodeRunReport(
                outcome: .startedAndRan, chain: tip.chain, blockHeight: tip.height,
                blocksBehind: tip.blocksBehind, heightAgeMinutes: nil,
                secondsRunning: stopWhenFinished ? ran : nil,
                blocksSinceLastCheck: sinceLastCheck, connections: peers
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
            RunLog.failed(
                "live reading failed: \(error.localizedDescription)", msSinceStart: ms())
            return nil
        }
    }

    /// Asks the node to stop and waits at most `limit` for it. Returns whether it
    /// finished in time.
    ///
    /// This bounds the *waiting*, not the shutdown — the shutdown itself still cannot
    /// be interrupted (ADR 0007), and this does not try to. The distinction is the
    /// whole point: a run that waits forever gets killed by the system and shows the
    /// person a timeout error, while a run that stops waiting returns cleanly and the
    /// daemon finishes on its own thread or dies with the process. Same outcome for
    /// the node, minus the error and minus the ungraceful kill of everything else.
    ///
    /// Polls rather than racing in a task group, because a group waits for every
    /// child before it returns — the loser would keep the run blocked exactly as
    /// before. The blocking wait itself is already on a detached thread
    /// (`NodeViewModel.performStop`), so the main actor stays free to poll.
    @MainActor
    private static func shutDown(
        session: NodeSession, within limit: Duration, ms: () -> Int
    ) async -> Bool {
        RunLog.mark("shutdown started", msSinceStart: ms())
        let progress = ShutdownProgress()
        Task { @MainActor in
            await session.node.performStop()
            progress.finished = true
        }
        let stopWaitingAt = ContinuousClock.now.advanced(by: limit)
        while ContinuousClock.now < stopWaitingAt {
            if progress.finished {
                RunLog.mark("shutdown finished", msSinceStart: ms())
                return true
            }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
        }
        RunLog.mark(
            "shutdown UNFINISHED after \(limit); returning without it", msSinceStart: ms())
        return false
    }

    /// Builds a report from the saved tip, since a node that is starting, stopping, or
    /// already shut down has no live figure to offer.
    @MainActor
    private static func savedReport(outcome: NodeRunOutcome) -> NodeRunReport {
        guard let last = NodeViewModel.lastKnown else {
            // Nothing has ever been recorded. Blocks-behind is -1 for "unknown" here
            // too: zero would claim the node is caught up at height zero.
            return NodeRunReport(
                outcome: outcome, chain: "unknown", blockHeight: 0,
                blocksBehind: -1, heightAgeMinutes: nil, secondsRunning: nil)
        }
        let age = Int(Date().timeIntervalSince(last.date) / 60)
        // Blocks-behind is unknown from a saved figure; it is reported as -1 rather
        // than 0, because 0 would claim the node is caught up.
        return NodeRunReport(
            outcome: outcome, chain: last.chain, blockHeight: last.height,
            blocksBehind: -1, heightAgeMinutes: age, secondsRunning: nil)
    }

    private static func finish(
        _ report: NodeRunReport, ms: Int
    ) -> some IntentResult & ReturnsValue<NodeRunReport> & ProvidesDialog {
        RunLog.finished(
            outcome: report.outcome.rawValue, height: report.blockHeight, msSinceStart: ms)
        return .result(value: report, dialog: IntentDialog(stringLiteral: report.summary))
    }
}

/// Publishes the action so it appears in Shortcuts and can be added to a Home
/// automation. Gated by availability rather than a compile-time condition, because
/// this list accepts only platform-availability conditions.

#endif
