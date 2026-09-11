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
// Development/Specs/003-node-automation-action/plan.md §2.
#if os(iOS)

/// How a run ended, as something a following automation step can branch on.
///
/// The plain text behind each case is what a person's automation compares against, so
/// these strings are a lasting commitment: renaming one silently changes the meaning of
/// a comparison someone already built.
enum NodeRunOutcome: String, AppEnum {
    /// The node was started and answered.
    case started
    /// A node was already running, so it was read and left alone.
    case alreadyRunning
    /// Declined before starting — device conditions, or the private network not ready.
    case declined
    /// Started, but did not answer within the time this run had.
    case didNotComeUp

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Node Run Outcome" }

    static var caseDisplayRepresentations: [NodeRunOutcome: DisplayRepresentation] {
        [
            .started: "Started",
            .alreadyRunning: "Already running",
            .declined: "Declined",
            .didNotComeUp: "Did not come up in time",
        ]
    }

    /// Derived from the plain outcome the framework-free logic produces, rather than
    /// chosen separately. The two cannot be one type: a value a following automation
    /// step can compare against needs plain text behind each case, which Swift does not
    /// allow alongside cases carrying extra data. Deriving one from the other means
    /// adding a way for a run to end will not compile until it is accounted for here —
    /// something no test could enforce as reliably.
    init(_ outcome: NodeAutomation.Outcome) {
        switch outcome {
        case .started: self = .started
        case .alreadyRunning: self = .alreadyRunning
        case .declined: self = .declined
        case .didNotComeUp: self = .didNotComeUp
        }
    }

    /// The plain form, for the decisions that must stay testable.
    ///
    /// The mirror of `init(_:)` above, and exhaustive for the same reason: a run that
    /// can end a new way will not compile until both directions account for it.
    var plain: NodeAutomation.Outcome {
        switch self {
        case .started: .started
        case .alreadyRunning: .alreadyRunning
        case .declined: .declined
        case .didNotComeUp: .didNotComeUp
        }
    }
}

/// What a run hands back.
///
/// Each named entry is usable as its own value in the next step of someone's
/// automation, so **the names are a commitment** — renaming or removing one breaks
/// automations already built on it.
///
/// A number that is absent means **not measured**, which is a different claim from
/// zero. Zero blocks behind means "measured, and caught up"; absent means nobody
/// looked. Reporting one as the other is how a report starts lying.
struct NodeRunReport: TransientAppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Node Run Report" }

    @Property(title: "Outcome") var outcome: NodeRunOutcome
    /// Which chain the height belongs to. A height means nothing without it.
    @Property(title: "Chain") var chain: String
    @Property(title: "Block height") var blockHeight: Int
    /// Headers the node knows about but has not yet downloaded as full blocks. Without
    /// this a height reads as "caught up" when the node may be far behind.
    @Property(title: "Blocks behind") var blocksBehind: Int?
    /// Blocks arrived since the last height this app recorded — which spans the minutes
    /// the node kept running after an earlier run returned, not just this run. Absent
    /// when no height has ever been recorded, or the chain changed.
    @Property(title: "Blocks since last check") var blocksSinceLastCheck: Int?
    /// Peers the node had when it was read. Absent if it could not be asked.
    @Property(title: "Connections") var connections: Int?
    /// The one sentence a person reads or hears.
    @Property(title: "Summary") var summary: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(summary)")
    }

    init() {}

    init(
        outcome: NodeRunOutcome,
        chain: String,
        blockHeight: Int,
        blocksBehind: Int? = nil,
        blocksSinceLastCheck: Int? = nil,
        connections: Int? = nil,
        summary: String
    ) {
        self.init()
        self.outcome = outcome
        self.chain = chain
        self.blockHeight = blockHeight
        self.blocksBehind = blocksBehind
        self.blocksSinceLastCheck = blocksSinceLastCheck
        self.connections = connections
        self.summary = summary
    }
}

#endif
