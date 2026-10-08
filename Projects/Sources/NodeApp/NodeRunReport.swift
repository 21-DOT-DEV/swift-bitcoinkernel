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
/// these strings are a lasting commitment — each is assigned explicitly rather than
/// derived from the case name, so renaming a case cannot silently change the meaning
/// of a comparison someone already built. A test pins the strings themselves.
enum NodeRunOutcome: String, AppEnum {
    /// The node was started and answered.
    case started = "started"
    /// A node was already running, so it was read and left alone.
    case alreadyRunning = "alreadyRunning"
    /// Declined before starting — device conditions, or the private network not ready.
    case declined = "declined"
    /// Started — or found still starting — but did not answer within the time
    /// this run had.
    case didNotComeUp = "didNotComeUp"
    /// The node was asked but gave no usable answer — it never answered, or its
    /// answer arrived after the node was stopped or the run ended.
    case noAnswer = "noAnswer"

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Node Run Outcome" }

    static var caseDisplayRepresentations: [NodeRunOutcome: DisplayRepresentation] {
        [
            .started: "Started",
            .alreadyRunning: "Already running",
            .declined: "Declined",
            .didNotComeUp: "Did not come up in time",
            // Not "in time": the case also covers a real answer discarded because
            // the node was stopped or the run ended while the question was out.
            .noAnswer: "Did not answer",
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
        case .noAnswer: self = .noAnswer
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
        case .noAnswer: .noAnswer
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
    /// Which chain the height belongs to, as the node reports it over RPC —
    /// the wire identifier (`main`, `signet`, `regtest`), which is the honest
    /// value for an automation to compare against; display-name mapping for a
    /// person happens in the summary sentence. A height means nothing without
    /// it — and both are absent when nothing was measured.
    @Property(title: "Chain") var chain: String?
    /// The height the node reported. Absent when nothing was measured — a run that
    /// declined or got no usable answer must not hand back the last recorded height
    /// looking like a fresh reading.
    @Property(title: "Block height") var blockHeight: Int?
    /// Headers the node knows about but has not yet downloaded as full blocks. Without
    /// this a height reads as "caught up" when the node may be far behind.
    @Property(title: "Blocks behind") var blocksBehind: Int?
    /// Blocks arrived since the last height a run actually reported — before any
    /// run has returned, the last tip anyone observed stands in — which spans
    /// the minutes the node kept running after an earlier run returned, not just
    /// this run, and never collapses because a background poll saw the node in
    /// between. Absent when no baseline has been recorded, or the chain changed.
    @Property(title: "Blocks since last check") var blocksSinceLastCheck: Int?
    /// Peers the node had when it was read. Absent if it could not be asked.
    @Property(title: "Connections") var connections: Int?
    /// The one sentence a person reads or hears.
    @Property(title: "Summary") var summary: String
    /// The deferred-lookup template `summary` was resolved from — what the
    /// actions hand to `IntentDialog` so the system's own rendering can
    /// translate it. One template, two renderings: the report sentence and the
    /// dialog can never disagree. Not a `@Property` — the automation-facing
    /// contract keeps `summary` the resolved `String`. Absent only on a report
    /// built through `init()`, which the AppIntents machinery alone uses.
    var dialogTemplate: LocalizedStringResource?

    /// The text the actions put in `IntentDialog` — the stored template when
    /// the report carries one, else the already-resolved sentence passed
    /// through as a `%@` argument, which is the only form `init()` can
    /// produce. Never `LocalizedStringResource(stringLiteral:)`: that form
    /// treats the rendered sentence as a catalog *key*, so a lookup either
    /// misses (harmless but pointless) or collides with a real entry that
    /// happens to share the text (the system's dialog would show a different
    /// language than the report's own `summary`). The fallback gets a named
    /// key so the catalog entry documents itself instead of minting a bare
    /// `"%@"` a translator could mistake for real text.
    var dialogText: LocalizedStringResource {
        dialogTemplate ?? LocalizedStringResource(
            "run.report.rendered-summary",
            defaultValue: "\(summary)",
            comment: "Fallback for a report built by the AppIntents machinery: the summary arrives already rendered and passes through verbatim — there is nothing to translate.")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: dialogText)
    }

    init() {}

    init(
        outcome: NodeRunOutcome,
        chain: String?,
        blockHeight: Int?,
        blocksBehind: Int? = nil,
        blocksSinceLastCheck: Int? = nil,
        connections: Int? = nil,
        dialogTemplate: LocalizedStringResource
    ) {
        self.init()
        self.outcome = outcome
        self.chain = chain
        self.blockHeight = blockHeight
        self.blocksBehind = blocksBehind
        self.blocksSinceLastCheck = blocksSinceLastCheck
        self.connections = connections
        self.dialogTemplate = dialogTemplate
        self.summary = String(localized: dialogTemplate)
    }
}

#endif
