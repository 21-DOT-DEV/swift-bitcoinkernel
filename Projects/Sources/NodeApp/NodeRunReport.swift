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

/// How the watch over a syncing node ended, as something a following automation
/// step can branch on.
///
/// A second axis beside `NodeRunOutcome`: the outcome says what the run did to
/// the *node* — started it, found it running, declined — while this says what
/// the run concluded about *syncing*. The two are deliberately independent: a
/// run that reports `alreadyRunning` may still have watched the node catch up,
/// and an entry weigh-in refusal is `declined` on the first axis while reporting
/// `conditionsChanged` on this one.
///
/// The text behind each case is a lasting commitment for the same reason the
/// outcome's is — a saved automation compares against it — so each string is
/// assigned explicitly and a test pins the assignment. Cases may be appended;
/// renaming or renumbering breaks automations already built.
///
/// The framework-free twin is `NodeAutomation.SyncResult`, derived and read
/// back through `init(_:)` and `.plain` — the same two-way mapping
/// `NodeRunOutcome` keeps with `Outcome`, and exhaustive for the same reason:
/// adding a case on either side will not compile until the other accounts for
/// it.
enum NodeSyncResult: String, AppEnum {
    /// The node reached the tip — either the watch saw the catch-up happen, or
    /// the entry gate found it already there: flag clear, no header gap, a tip
    /// inside the freshness window — the same bar the watch's proof applies
    /// at every pass.
    case caughtUp = "caughtUp"
    /// The run's time ran out while the node was still behind.
    case stillSyncing = "stillSyncing"
    /// Nothing advanced for long enough that the watch gave up — the node
    /// stopped answering, or the readings stayed flat past the leash.
    case noProgress = "noProgress"
    /// The node was stopped from the app while the watch ran. "The run was
    /// stopped" cannot occur — a stopped run throws `CancellationError` and
    /// produces no report.
    case nodeStopped = "nodeStopped"
    /// Device conditions — a metered network, Low Data Mode, a critical thermal
    /// state, Low Power Mode switched on mid-watch — ended the watch, or
    /// refused it at the entry weigh-in.
    case conditionsChanged = "conditionsChanged"
    /// The run has no sync answer to give: it declined before the entry
    /// weigh-in, got no answer before the watch could begin, carried no watch
    /// budget (every short-action run), or found a regtest chain — where "still
    /// syncing" is ill-defined, so nothing is claimed rather than something
    /// vacuous.
    case notMeasured = "notMeasured"

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Node Sync Result" }

    static var caseDisplayRepresentations: [NodeSyncResult: DisplayRepresentation] {
        [
            .caughtUp: "Caught up",
            .stillSyncing: "Still syncing",
            .noProgress: "No progress",
            .nodeStopped: "Node stopped",
            .conditionsChanged: "Conditions changed",
            .notMeasured: "Not measured",
        ]
    }

    /// Derived from the plain sync verdict the framework-free logic produces,
    /// rather than chosen separately — the mirror of `NodeRunOutcome.init(_:)`.
    /// Adding a way a watch can end will not compile until it is accounted for
    /// here — something no test could enforce as reliably.
    init(_ result: NodeAutomation.SyncResult) {
        switch result {
        case .caughtUp: self = .caughtUp
        case .stillSyncing: self = .stillSyncing
        case .noProgress: self = .noProgress
        case .nodeStopped: self = .nodeStopped
        case .conditionsChanged: self = .conditionsChanged
        case .notMeasured: self = .notMeasured
        }
    }

    /// The plain form, for the decisions that must stay testable.
    ///
    /// The mirror of `init(_:)` above, and exhaustive for the same reason.
    var plain: NodeAutomation.SyncResult {
        switch self {
        case .caughtUp: .caughtUp
        case .stillSyncing: .stillSyncing
        case .noProgress: .noProgress
        case .nodeStopped: .nodeStopped
        case .conditionsChanged: .conditionsChanged
        case .notMeasured: .notMeasured
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
    /// How the watch over a syncing node ended — the second axis beside
    /// `outcome`, so an automation can branch on the sync verdict apart from
    /// what the run did to the node. Always set, never absent: `notMeasured`
    /// is the standing answer for every run that ended before the watch —
    /// declined, unanswered, carrying no budget, or on a regtest chain —
    /// while the entry weigh-in's refusal reports `conditionsChanged` and a
    /// run whose entry gate found the node already at the tip reports
    /// `caughtUp`.
    @Property(title: "Sync result") var syncResult: NodeSyncResult
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
    /// Heights the node gained while this run watched — the run-scoped counter
    /// beside `blocksSinceLastCheck`, which keeps its pre-run-baseline meaning.
    /// Absent when nobody watched, like every other number here — zero means
    /// "watched and gained nothing", which is a different claim.
    @Property(title: "Blocks gained this run") var blocksGainedThisRun: Int?
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

    /// `syncResult` and `blocksGainedThisRun` carry no defaults on purpose: a
    /// producer that omitted one would still compile and report "not measured"
    /// for a run that watched — plausible, and wrong. Requiring both is the
    /// same compile-forcing `NodeRunOutcome`'s two-way mapping keeps for
    /// endings: every report states its sync answer.
    init(
        outcome: NodeRunOutcome,
        syncResult: NodeSyncResult,
        chain: String?,
        blockHeight: Int?,
        blocksBehind: Int? = nil,
        blocksSinceLastCheck: Int? = nil,
        blocksGainedThisRun: Int?,
        connections: Int? = nil,
        dialogTemplate: LocalizedStringResource
    ) {
        self.init()
        self.outcome = outcome
        self.syncResult = syncResult
        self.chain = chain
        self.blockHeight = blockHeight
        self.blocksBehind = blocksBehind
        self.blocksSinceLastCheck = blocksSinceLastCheck
        self.blocksGainedThisRun = blocksGainedThisRun
        self.connections = connections
        self.dialogTemplate = dialogTemplate
        self.summary = String(localized: dialogTemplate)
    }
}

#endif
