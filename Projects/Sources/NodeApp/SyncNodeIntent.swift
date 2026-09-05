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

// Phone and tablet only. A home automation runs from a home hub — a HomePod, Apple
// TV, or iPad — and never from a Mac, so this feature's purpose is unreachable there.
// See Development/Specs/003-node-automation-action/plan.md §2.
//
// Excluded at compile time rather than by an availability annotation: an annotation
// still compiles the file on macOS and only refuses it at runtime, which would ship
// the action's code into a build that must never offer it. `os(iOS)` covers both
// iPhone and iPad.
#if os(iOS)

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
    @Property(title: "Block height") var blockHeight: Int
    @Property(title: "Blocks behind") var blocksBehind: Int
    /// Minutes since the height was recorded, when it came from saved data rather
    /// than a live reading. Absent means the figure is live.
    @Property(title: "Height age in minutes") var heightAgeMinutes: Int?

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(summary)") }

    var summary: String {
        switch outcome {
        case .startedAndRan:
            return blocksBehind > 0
                ? "Ran at height \(blockHeight), \(blocksBehind) blocks behind."
                : "Ran at height \(blockHeight)."
        case .alreadyRunning:
            return "Already running; left alone. Height \(blockHeight)\(ageSuffix)."
        case .waitingOnPrivateNetwork:
            return "Spent the run establishing the private network; the node did not start."
        case .couldNotStart:
            return "Could not start."
        }
    }

    private var ageSuffix: String {
        guard let heightAgeMinutes else { return "" }
        return " (recorded \(heightAgeMinutes) minutes ago)"
    }

    init() {}

    init(outcome: NodeRunOutcome, blockHeight: Int, blocksBehind: Int, heightAgeMinutes: Int?) {
        self.init()
        self.outcome = outcome
        self.blockHeight = blockHeight
        self.blocksBehind = blocksBehind
        self.heightAgeMinutes = heightAgeMinutes
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
        let session = NodeSession.shared
        let defaults = UserDefaults.standard
        let privacyEnabled = defaults.bool(forKey: "tor_enabled")

        switch NodeAutomation.step(
            nodeIsStopped: session.node.nodeState == .stopped,
            privacyEnabled: privacyEnabled,
            privacyReady: session.tor.isReady
        ) {
        case .reportExistingNode:
            return Self.finish(Self.savedReport(outcome: .alreadyRunning))

        case .waitForPrivateNetwork:
            // A cold start cannot finish inside one window; spending the window on it
            // anyway leaves the cache warm, so the next run starts from 5–10 seconds
            // rather than 30–60. Readiness, not syncing, is this run's purpose.
            session.tor.start()
            try? await Task.sleep(for: NodeAutomation.holdWindow)
            return Self.finish(Self.savedReport(outcome: .waitingOnPrivateNetwork))

        case .startNode:
            let arguments: [String]
            do {
                arguments = try NodeAutomation.startArguments(
                    privacyEnabled: privacyEnabled,
                    proxyAddress: session.tor.proxyAddress,
                    build: { DaemonConfig.buildArguments(torProxy: $0) }
                )
            } catch {
                // ADR 0006: never start on a direct connection.
                return Self.finish(Self.savedReport(outcome: .waitingOnPrivateNetwork))
            }

            let socksPort = privacyEnabled
                ? session.tor.socksEndpoint.map { UInt16(clamping: $0.port) }
                : nil
            session.node.start(
                arguments: arguments,
                torSession: privacyEnabled ? session.tor.sessionID : nil,
                torSocksPort: socksPort
            )
            session.startedByAutomation = true

            try? await Task.sleep(for: NodeAutomation.holdWindow)

            // The action watches its own clock rather than waiting to be told time is
            // up (ADR 0007): shutdown here cannot be interrupted once begun, and a
            // stop signal could not begin one.
            await session.node.performStop()
            session.startedByAutomation = false

            return Self.finish(Self.savedReport(outcome: .startedAndRan))
        }
    }

    /// Builds a report from the saved tip, since a node that is starting, stopping, or
    /// already shut down has no live figure to offer.
    @MainActor
    private static func savedReport(outcome: NodeRunOutcome) -> NodeRunReport {
        guard let last = NodeViewModel.lastKnown else {
            return NodeRunReport(outcome: outcome, blockHeight: 0, blocksBehind: 0, heightAgeMinutes: nil)
        }
        let age = Int(Date().timeIntervalSince(last.date) / 60)
        return NodeRunReport(
            outcome: outcome, blockHeight: last.height, blocksBehind: 0, heightAgeMinutes: age
        )
    }

    private static func finish(
        _ report: NodeRunReport
    ) -> some IntentResult & ReturnsValue<NodeRunReport> & ProvidesDialog {
        .result(value: report, dialog: IntentDialog(stringLiteral: report.summary))
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
