//
//  NodeRunReport.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import AppIntents
import Foundation

// Phone and tablet only, for the reason recorded in
// Development/Specs/003-node-automation-action/plan.md §2. Excluded at compile
// time rather than by an availability annotation, which would still compile this
// into a Mac build and only refuse it at runtime.
#if os(iOS)

enum NodeRunOutcome: String, AppEnum {
    case startedAndRan
    case alreadyRunning
    case waitingOnPrivateNetwork
    case couldNotStart

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Node Run Outcome" }

    static var caseDisplayRepresentations: [NodeRunOutcome: DisplayRepresentation] {
        [
            .startedAndRan: "Started and ran",
            .alreadyRunning: "Already running",
            .waitingOnPrivateNetwork: "Waiting on private network",
            .couldNotStart: "Could not start",
        ]
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
extension NodeRunOutcome {
/// Derived from the fuller description rather than chosen separately.
///
/// The two lists cannot be one type — a list Shortcuts can branch on must have a
/// plain text value behind each case, and Swift does not allow that alongside
/// extra data attached to each case. Deriving one from the other is the next best
/// thing: adding a new way for a run to end will not compile until it is accounted
/// for here, which no test could enforce as reliably.
init(_ outcome: RunOutcome) {
    switch outcome {
    case .adopted: self = .alreadyRunning
    case .refusedPrivateNetworkUnavailable: self = .waitingOnPrivateNetwork
    case .failed: self = .couldNotStart
    case .completed: self = .startedAndRan
    }
}
}

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
    /// How long the run waited before stopping the node. Absent unless it was
    /// asked to stop, because otherwise it does not wait at all. Absent means not
    /// measured; zero would mean measured and nothing, which is a different claim.
    @Property(title: "Seconds running") var secondsRunning: Double?
    /// Blocks arrived since the last height this app recorded. That spans the
    /// minutes the node keeps running after an earlier action returned, not just
    /// this run. Absent when no height has ever been recorded.
    @Property(title: "Blocks since last check") var blocksSinceLastCheck: Int?
    /// Connections the node had when the run stopped it. Absent unless the run
    /// waited, since at the moment a node first answers it has none yet.
    @Property(title: "Connections") var connections: Int?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(summary)")
    }

    var summary: String {
        switch outcome {
        case .startedAndRan:
            let behind = blocksBehind > 0 ? ", \(blocksBehind) behind" : ""
            let since = blocksSinceLastCheck.map { " \($0) blocks since the last check." } ?? ""
            return "Node running on \(chain) at height \(blockHeight)\(behind).\(since)"
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

    init(
        outcome: NodeRunOutcome, chain: String, blockHeight: Int, blocksBehind: Int,
        heightAgeMinutes: Int?, secondsRunning: Double?,
        blocksSinceLastCheck: Int? = nil, connections: Int? = nil
    ) {
        self.init()
        self.outcome = outcome
        self.chain = chain
        self.blockHeight = blockHeight
        self.blocksBehind = blocksBehind
        self.heightAgeMinutes = heightAgeMinutes
        self.secondsRunning = secondsRunning
        self.blocksSinceLastCheck = blocksSinceLastCheck
        self.connections = connections
    }
}

#endif
