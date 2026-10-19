//
//  NodeAutomation.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Bitcoin
import Foundation

/// The decisions an unattended run makes, expressed as plain values.
///
/// Deliberately free of any Shortcuts or SwiftUI type, so they can be unit-tested
/// without a node, a screen, or the address-hiding network. The run that calls
/// them (`NodeRun`) orchestrates and does no deciding — every judgment
/// it appears to make is one of these. See
/// `Development/Specs/003-node-automation-action/plan.md` §3 and §7.
enum NodeAutomation {

    /// What an unattended run should do next.
    enum Step: Equatable {
        /// A node is already running (or still shutting down), so report on it
        /// and change nothing. An automation must never interrupt a node someone
        /// started themselves (ADR 0005).
        case reportExistingNode
        /// A node is already on its way up — started by an earlier run that ran
        /// out of time, or by the app itself. It cannot be started again and it
        /// cannot answer questions yet, so the run waits on it like one it
        /// started itself, then reports it as found rather than started.
        case waitForStartingNode
        /// The privacy setting is on but the network is not established yet; spend
        /// the window establishing it rather than starting the node.
        case waitForPrivateNetwork
        /// Nothing in the way; start the node.
        case startNode
    }

    /// Decides the next step from three plain facts.
    static func step(nodeState: NodeState, privacyEnabled: Bool, privacyReady: Bool) -> Step {
        switch nodeState {
        case .running, .stopping:
            // A node still shutting down is read like a running one on purpose:
            // it cannot be started (`start()` refuses anything but `.stopped`),
            // and the read path's answer checks land it on `noAnswer` if it
            // finishes stopping mid-question.
            return .reportExistingNode
        case .starting:
            // Mid-startup is neither running nor startable: the node cannot
            // answer until its block index loads — measured at up to two minutes
            // on a locked phone — so reading it once would almost certainly end
            // in `noAnswer`, while `start()` would refuse it. The run waits.
            return .waitForStartingNode
        case .stopped:
            if privacyEnabled && !privacyReady { return .waitForPrivateNetwork }
            return .startNode
        }
    }

    /// Whether a step is weighed against the device conditions `NodePreflight`
    /// reads.
    ///
    /// Conditions gate starting, not reporting or waiting: each one protects
    /// something a start spends — gigabytes of sync on a metered link, battery,
    /// heat — and a run that only reads an already-running node, or waits on an
    /// already-starting one, spends none of it. Gating this way also means
    /// "not started" is never claimed about a node that is.
    ///
    /// `waitForPrivateNetwork` counts as a start. Establishing the network costs
    /// a consensus download over whatever link is current, so the network
    /// conditions still apply — and the run's whole purpose is the node start a
    /// later run will attempt, so a device that could never start one (no chain
    /// folder, no disk) has no use for the network either.
    static func consultsDeviceConditions(for step: Step) -> Bool {
        switch step {
        case .startNode, .waitForPrivateNetwork:
            return true
        case .reportExistingNode, .waitForStartingNode:
            return false
        }
    }

    /// Whether an answer that has just arrived from the node may still be reported.
    ///
    /// The channel used to question the node cannot be interrupted once a question is
    /// in flight: underneath it is a plain synchronous call that runs to completion and
    /// hands back an answer regardless of what happened while it was away. Two things
    /// can happen in that window. The run can be called off — the person taps stop on
    /// the progress card, or the system runs out of patience. Or the node can be shut
    /// down from inside the app by someone who opened it mid-wait — including one
    /// still shutting down, since a node on its way down is no longer the node the
    /// answer described.
    ///
    /// In both cases the answer is real but nobody is waiting for it, and reporting it
    /// would claim a success that contradicts what the person just did. Both facts must
    /// be read *after* the answer arrives; reading them beforehand answers a question
    /// about a moment that has already passed.
    static func answerIsStillWanted(runWasCancelled: Bool, nodeIsStopped: Bool) -> Bool {
        !runWasCancelled && !nodeIsStopped
    }

    /// What the system's progress card should show once a run has finished.
    ///
    /// The card is the display the system puts on screen for a run that outlives the
    /// usual background time limit: a headline, a line of detail, and a bar. The app
    /// supplies all three.
    struct Ending: Equatable {
        /// Whether the bar is filled.
        ///
        /// Only an earned ending fills: a run that actually read a node and
        /// carried no watch to serve (the `notMeasured` paths), or a watch
        /// that finished the one way that completes the bar's claim —
        /// `caughtUp`. A run that declined, got no answer, or ended its
        /// watch on `stillSyncing`/`noProgress`/`conditionsChanged` did not
        /// finish the work the bar describes — and filling the bar for those
        /// tells the person the opposite of what happened.
        let fillsProgressBar: Bool
        /// The card's headline: what became of the node, in two or three words.
        let title: String
        /// The line beneath it — the run's own summary sentence, which is the one piece
        /// of text in the whole feature written to be read by a person.
        let detail: String
    }

    /// The headline shown while a run is still going.
    ///
    /// Worded to stay honest on every path: a run that finds a node already up only
    /// *reads* it, so a headline like "Starting Bitcoin node" would claim work that
    /// path never does. "Checking" covers starting, waiting, and reading alike.
    static let inProgressTitle = "Checking the Bitcoin node"

    /// The headline the card flips to once a watch begins (FR-003 — the plan
    /// §3.4 wording, pinned). Distinct from `inProgressTitle`: "checking"
    /// covers starting, waiting, and reading, while a committed watch is
    /// doing exactly one thing — "syncing" is the honest verb for it.
    static let watchingTitle = "Syncing the Bitcoin node"

    /// Turns a finished run into what the card shows.
    ///
    /// Kept here, beside `summary(...)`, because it is a judgment about what the person
    /// is told — not display plumbing. The bar and the words are decided together so
    /// they cannot end up contradicting each other, which is the failure this replaced:
    /// the bar was previously filled for every ending, including runs that refused to
    /// start.
    ///
    /// `syncEnding` is required for the same reason `NodeRunReport` requires
    /// it: a producer that could omit the sync answer could still claim a
    /// card that disagrees with the field. When it is real, the sync ending
    /// owns the headline — the card's job is to say how *syncing* ended, and
    /// the detail line keeps the whole sentence for everything else. The
    /// two frames an ending can arrive in are distinct cases: a watch that
    /// saw the catch-up earns "Caught up", while an entry gate that found
    /// the node already there reads "Synced to tip" — nothing was caught
    /// up *by* the run. The same split holds for conditions: mid-watch
    /// drift says what changed, a weigh-in refusal says the watch did not
    /// start.
    static func ending(
        outcome: Outcome, syncEnding: SyncEnding, summary: String
    ) -> Ending {
        assert(
            isCoherent(outcome: outcome, ending: syncEnding),
            "\(outcome) cannot carry \(syncEnding)")
        let title: String
        switch syncEnding {
        case .caughtUp:
            title = "Caught up"
        case .alreadyAtTip:
            title = "Synced to tip"
        case .stillSyncing:
            title = "Still syncing"
        case .noProgress:
            title = "No progress"
        case .nodeStopped:
            title = "Node stopped"
        case .conditionsChanged:
            title = "Conditions changed"
        case .watchRefused:
            // A weigh-in refusal means nothing changed — the condition
            // stood and the watch never began, so "changed" would be a
            // lie. "Watch not started" parallels "Node not started" for
            // `.declined`.
            title = "Watch not started"
        case .notMeasured:
            switch outcome {
            case .started: title = "Node running"
            case .alreadyRunning: title = "Node already running"
            case .didNotComeUp: title = "Node still starting"
            case .noAnswer: title = "Node did not answer"
            case .declined: title = "Node not started"
            }
        }
        return Ending(
            fillsProgressBar: syncEnding.result == .caughtUp
                || (syncEnding == .notMeasured
                    && (outcome == .started || outcome == .alreadyRunning)),
            title: title,
            detail: summary)
    }

    /// What the card shows when the system — not the person — ends the run.
    ///
    /// A timeout means the run went quiet long enough for the system to withdraw
    /// the extended window; nobody dismissed the card, so it is owed an honest
    /// ending. The bar is deliberately not filled — the run never finished the
    /// work it describes — and the node itself is left running either way.
    static let timedOutEnding = Ending(
        fillsProgressBar: false,
        title: "Run cut short",
        detail: "The system ended the run early. The node itself was not stopped.")

    /// Whether the launch-time privacy floor is engaged, given the preference
    /// as the run's snapshot froze it and as it reads right now.
    ///
    /// The answer is the OR of the two — privacy fails closed in both
    /// directions. A person who turns Tor *on* while a run is in flight has
    /// just asked for privacy; launching direct then would leak their address
    /// moments after the ask. And a snapshot that required privacy keeps the
    /// run private-or-nothing if the toggle was since switched *off* —
    /// `startArguments` turns that split into a decline rather than a private
    /// launch onto a network whose teardown the toggle just ordered, and a
    /// mid-flight flip is never answered with a direct connection. The worst
    /// case of either direction is a decline, never a leak (ADR 0006).
    /// `StartRefusal(stillEnabled:)` is fed the same live flag to pick its
    /// sentence — the read itself lives in `NodeSession`. The answer must
    /// also be written back into the snapshot's `torEnabled` before
    /// `buildArguments(settings:)` runs — the builder adds `-proxy=` only from
    /// that flag, so a live-on flip that skips this step passes the check and
    /// still launches direct. Everything else the run launches from the
    /// snapshot alone.
    ///
    /// The run feeds it the snapshot's `torEnabled` and a live re-read of the
    /// `tor_enabled` flag — one of two live reads of that flag the run is
    /// allowed, the other being `NodeSession.startTorIfStillEnabled(reading:)`'s.
    /// `startArguments` weighs the same pair to decline the turned-off split —
    /// a second decision on the same read, not a third read. Every other key
    /// stays frozen in the snapshot.
    static func requiresPrivateNetwork(
        snapshotEnabled: Bool, liveEnabled: Bool
    ) -> Bool {
        snapshotEnabled || liveEnabled
    }

    /// Why a launch was refused for want of the private network: it was on but
    /// not answering yet, or it had been switched off while the run was in
    /// flight — two different sentences, because the first promises it is being
    /// established and the second must not.
    enum StartRefusal: Error, Equatable {
        case privateNetworkNotReady
        /// The person switched the network off while the run was in flight —
        /// nothing is being established, so the not-ready sentence would be a lie.
        case privateNetworkTurnedOff

        /// Which refusal applies when the network is unavailable depends on
        /// the live setting alone: still on means it is genuinely coming up,
        /// switched off means nothing is being established — and "being
        /// established now" would then be a false sentence. The deliberate
        /// wait-for-it path feeds it the live flag from
        /// `startTorIfStillEnabled(reading:)`; the launch boundary reports the case
        /// `startArguments` threw instead — it already holds the
        /// snapshot/live split, so it skips the picker.
        init(stillEnabled: Bool) {
            self = stillEnabled ? .privateNetworkNotReady : .privateNetworkTurnedOff
        }

        /// The single sentence a person sees, kept beside the case so the
        /// wording cannot drift between the paths that decline for this reason —
        /// the one that waits for the network on purpose and the one that finds
        /// it gone at the last moment. A template rather than a rendered string,
        /// like `NodePreflight.Refusal.message`, so the system's dialog can
        /// localize it.
        var message: LocalizedStringResource {
            switch self {
            case .privateNetworkNotReady:
                return "The private network was not ready, so the node did not start. It is being established now; try again shortly."
            case .privateNetworkTurnedOff:
                return "The private network was turned off, so the node did not start."
            }
        }
    }

    /// Builds the daemon's launch arguments, refusing outright when the launch
    /// boundary's privacy rules say no — either the setting was switched off
    /// mid-flight, or privacy is required and no *usable* proxy address exists
    /// (`nil`, an empty string, and a whitespace-only string all read as
    /// "not ready").
    ///
    /// The off-flip is checked first: a snapshot that required privacy whose
    /// setting now reads off means the network it would bind to is the one the
    /// screen was just told to tear down — the preference write lands a step
    /// before `stop()` runs, so a still-reporting endpoint in that instant is
    /// already dying. Declining there costs a run; launching binds the node to
    /// a proxy that dies seconds after the report says "started".
    ///
    /// The shared argument builder adds the proxy only when the address is
    /// non-`nil`, so a non-`nil` empty string slips past as if it were a real
    /// proxy and starts the node with a blank proxy setting — that is, on a
    /// direct connection, sending the person's home network address to peers
    /// after they asked it not to. Refusing only `nil` would leave that hole
    /// open, so this is a privacy floor: anything that is not a real address is
    /// refused while either the snapshot or the live setting requires privacy.
    /// (The policy is ADR 0006.)
    ///
    /// The value forwarded to the builder is the trimmed one, so surrounding
    /// whitespace never reaches the daemon as part of a `-proxy=` argument.
    ///
    /// - Parameter build: the shared argument builder, taking a proxy address.
    /// - Throws: the `StartRefusal` that applies, so the run can report the
    ///   verdict it was actually given rather than re-derive it.
    static func startArguments(
        snapshotEnabled: Bool,
        liveEnabled: Bool,
        proxyAddress: String?,
        build: (String?) -> [String]
    ) throws(StartRefusal) -> [String] {
        if snapshotEnabled && !liveEnabled {
            throw StartRefusal.privateNetworkTurnedOff
        }
        let trimmedProxy = proxyAddress?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasUsableProxy = !(trimmedProxy?.isEmpty ?? true)
        let privacyEnabled = requiresPrivateNetwork(
            snapshotEnabled: snapshotEnabled, liveEnabled: liveEnabled)
        if privacyEnabled && !hasUsableProxy { throw StartRefusal.privateNetworkNotReady }
        return build(trimmedProxy)
    }

    // MARK: - Turning what the node said into what a run reports

    /// The figures a report needs, all taken from one reading so they cannot disagree
    /// with each other.
    struct LiveReading: Equatable {
        let chain: String
        let height: Int
        /// Headers known but not yet downloaded as full blocks.
        let blocksBehind: Int
        /// Whether the node still reports itself in initial block download —
        /// the flag Bitcoin Core latches and clears on its own 24-hour tip-age
        /// rule, and the watch's first "still syncing" signal.
        let isInitialBlockDownload: Bool
        /// The best header the node holds — the watch's live denominator, and
        /// the height a confirming peer's `synced_headers` is weighed against.
        /// `blocksBehind` already carries the gap this opens; the watch needs
        /// the absolute figure itself.
        let headers: Int
        /// The tip's own timestamp — the "still syncing" signal that survives
        /// a warm restart, where the flag is already clear at chain-tip load
        /// and no header gap has been fetched yet. Miner-set and
        /// consensus-tolerant to ~2 h in the future, so staleness inside that
        /// band is invisible to it; anything older still enters the watch.
        let tipTime: Date
    }

    /// Reads the node's own chain summary, reusing the value types the on-screen
    /// dashboard already computes rather than re-deriving them.
    static func reading(from info: BlockchainInfo) -> LiveReading {
        let sync = SyncSummary(info)
        return LiveReading(
            chain: info.chain, height: sync.blocks, blocksBehind: sync.headersAhead,
            isInitialBlockDownload: sync.isInitialBlockDownload, headers: sync.headers,
            tipTime: info.time.date)
    }

    /// What a single peer answered, pared to the two facts the watch's catch-up
    /// proof can weigh — the `getpeerinfo` fields the `caughtUp` peer
    /// confirmation counts (FR-006).
    ///
    /// Kept beside `LiveReading` rather than folded into it: the watch asks
    /// `getpeerinfo` only on the flat passes that cannot otherwise prove a
    /// catch-up, so a peer answer is evidence a pass may carry — it is not a
    /// chain reading and never resets a leash.
    struct PeerEvidence: Equatable {
        /// `synced_headers` — the best height the peer has announced that the
        /// node already holds (`nSyncHeight`/`pindexBestKnownBlock`, which
        /// only ever points into our own index), or −1 until it announces
        /// anything held — which simply never equals a real `headers`. Against
        /// a reading's `headers`, equality is a completed exchange: Core
        /// itself asks every block-serving peer from one block back of a tip
        /// under a day old, so a current peer's answer is never empty, and it
        /// proves the peer knows nothing higher than our tip (a same-height
        /// fork would satisfy it too — height, not block identity, is the
        /// question the proof asks).
        let syncedHeaders: Int

        /// The connection's resolved kind. Only `outboundFullRelay` and
        /// `blockRelayOnly` ever count toward the proof — inbound peers are
        /// attacker-selected — and an absent `connection_type` field resolves
        /// by direction: `.inbound`, which is still never countable, or
        /// `unresolvedOutbound`, which matches no wire kind and so cannot
        /// qualify by accident.
        let connectionType: ConnectionType

        /// The `connection_type` vocabulary, as named constants over the wire
        /// string.
        ///
        /// Open-ended deliberately: a value the list has not been taught —
        /// including any a future Core adds — decodes losslessly and simply
        /// fails to match a named constant, which is the fail-closed direction
        /// the proof wants.
        struct ConnectionType: RawRepresentable, Equatable {
            let rawValue: String

            static let inbound = Self(rawValue: "inbound")
            static let outboundFullRelay = Self(rawValue: "outbound-full-relay")
            static let blockRelayOnly = Self(rawValue: "block-relay-only")
            static let manual = Self(rawValue: "manual")
            static let feeler = Self(rawValue: "feeler")
            static let addrFetch = Self(rawValue: "addr-fetch")
            /// This fork's own kind — a short-lived outbound connection to a
            /// privacy network, opened to relay the person's own transactions
            /// and closed after (`Vendor/bitcoin`'s
            /// `ConnectionType::PRIVATE_BROADCAST`). Self-initiated but never
            /// block-serving, so it does not count.
            static let privateBroadcast = Self(rawValue: "private-broadcast")
            /// Not a wire value: what an absent `connection_type` resolves to
            /// on an outbound peer (`PeerInfo.resolvedConnectionType`). It
            /// deliberately equals no real kind — an outbound peer the node
            /// could not classify is never counted as block-serving.
            static let unresolvedOutbound = Self(rawValue: "outbound")
        }

        init(_ peer: PeerInfo) {
            syncedHeaders = peer.syncedHeaders
            connectionType = ConnectionType(rawValue: peer.resolvedConnectionType)
        }
    }

    /// The little a persisted tip knows — the chain it was on and the height it
    /// stood at when last written.
    ///
    /// Deliberately not a `LiveReading`: a baseline is read back from a store,
    /// not measured from the node, so it carries only the two facts that were
    /// written. The watch's questions — the IBD flag, the header height, the
    /// tip's age — have no honest answers on a baseline, and keeping it a
    /// separate type means they can never be asked of one. `blocksSince` is
    /// its whole consumer; a live reading serves as a baseline by the same
    /// projection (chain and height are all a baseline keeps).
    struct TipBaseline: Equatable {
        let chain: String
        let height: Int
    }

    /// Blocks between a baseline and a reading — "since" whichever baseline the
    /// caller supplies — or `nil` when that cannot be known.
    ///
    /// The name promises no particular baseline: the run passes its pre-run
    /// snapshot (a `last_run_*` tip, or the `last_known_*` fallback), which is
    /// what makes the report's figure "blocks since the last check"; the watch
    /// passes its entry heights as the baseline once it reuses this for
    /// "gained this run".
    /// `nil` when either side is missing, or when the two are of **different
    /// chains** — subtracting a testnet height from a mainnet one would produce
    /// a confident-looking nonsense number. Never negative: a height that went
    /// backwards (a chain reorganisation, or a rebuilt index) is reported as no
    /// gain rather than a negative one.
    static func blocksSince(previous: TipBaseline?, to current: LiveReading?) -> Int? {
        guard let previous, let current, previous.chain == current.chain else { return nil }
        return max(0, current.height - previous.height)
    }

    /// How a run ended, as a plain value.
    ///
    /// Kept separate from the Shortcuts-facing outcome type on purpose: this file is
    /// deliberately free of framework types so it can be tested on every platform,
    /// including where the Shortcuts types do not exist. The Shortcuts-facing type is
    /// derived from this one, so adding a case here will not compile until it is
    /// accounted for there.
    enum Outcome: Equatable {
        case started
        case alreadyRunning
        case declined
        case didNotComeUp
        /// The node was asked and nothing usable came back — it never answered,
        /// or its answer arrived after the node was stopped or the run ended.
        /// Real answers that land too late are discarded rather than reported,
        /// so this outcome claims no measurement was made, which is true.
        case noAnswer
    }

    /// The single sentence a person reads or hears, derived from the same values the
    /// named fields carry so the two can never disagree.
    ///
    /// A *template*, not a rendered string — the actions hand it to `IntentDialog`
    /// unresolved, so the system's own rendering localizes the sentence the report
    /// also carries. That is why the numbers go in as raw integers rather than
    /// through `formatted()`: the resolver applies the locale's digit grouping at
    /// display time, and pre-formatting them would both freeze the app's locale into
    /// the dialog and cut the count loose from the catalog's plural variants.
    ///
    /// The duration style a `noProgress` sentence uses for the measured
    /// silence — wide units ("4 minutes"), hours and minutes only. A shared
    /// static so the wording and the tests asserting it cannot drift apart.
    static let summarySilenceFormat = Duration.UnitsFormatStyle(
        allowedUnits: [.minutes, .hours], width: .wide)

    /// The card detail line's duration style — abbreviated ("3 min") for
    /// the terse `localizedAdditionalDescription` idiom. Shared for the
    /// same reason as `summarySilenceFormat`.
    static let detailSilenceFormat = Duration.UnitsFormatStyle(
        allowedUnits: [.minutes, .hours], width: .abbreviated)

    /// The single sentence a person reads or hears, derived from the same
    /// values the named fields carry so the two can never disagree.
    ///
    /// `syncEnding` is required for the same reason `NodeRunReport` requires
    /// it: a producer that could omit the sync answer could still produce a
    /// sentence disagreeing with the field. `notMeasured` reproduces the
    /// pre-watch sentence exactly — the short action's output is unchanged.
    /// A real ending appends its own sentence at a sentence boundary (the
    /// run's history first, its verdict last), except `nodeStopped`, which
    /// rewrites the lead-in wholesale: "Node running" is a lie once the app
    /// has stopped it.
    ///
    /// The two frames an ending can arrive in are distinct cases, so the
    /// wording can never conflate them: the entry gate's `alreadyAtTip`
    /// versus a watch's `caughtUp`, the weigh-in's `watchRefused` versus
    /// mid-watch `conditionsChanged`. The endings that name a detail carry
    /// it — a `nil` silence or refusal produces the generic honest ending
    /// rather than a fabricated detail.
    static func summary(
        outcome: Outcome,
        syncEnding: SyncEnding,
        chain: String,
        height: Int,
        blocksBehind: Int?,
        blocksSinceLastCheck: Int?,
        declinedReason: LocalizedStringResource?
    ) -> LocalizedStringResource {
        assert(
            isCoherent(outcome: outcome, ending: syncEnding),
            "\(outcome) cannot carry \(syncEnding)")
        switch outcome {
        case .declined:
            // The reason is the whole message: it is the only thing that tells the
            // person what to change.
            return declinedReason ?? "The node did not start."
        case .didNotComeUp:
            // Deliberately silent on who started it: `waitForStarting` reaches
            // this for a node already coming up — including one that appeared
            // during the condition read — so "was started" would claim agency
            // this run may not have.
            return "The node had not come up yet, so nothing was measured."
        case .noAnswer:
            return "The node did not answer, so nothing was measured."
        case .alreadyRunning, .started:
            // The node's wire name is not fit for a sentence a person reads —
            // the display name the settings picker shows is. A name with no
            // counterpart ("testnet4", a fork's) stays verbatim rather than
            // mislabeled.
            let chainName = BitcoinNetwork(rpcChain: chain)?.rawValue ?? chain
            let headline: LocalizedStringResource =
                if let blocksBehind, blocksBehind > 0 {
                    outcome == .started
                        ? "Node running on \(chainName) at block \(height), \(blocksBehind) behind."
                        : "A node was already running on \(chainName) at block \(height), \(blocksBehind) behind."
                } else {
                    outcome == .started
                        ? "Node running on \(chainName) at block \(height)."
                        : "A node was already running on \(chainName) at block \(height)."
                }
            var text = headline
            if case .nodeStopped = syncEnding {
                // The app stopped the node mid-watch, so the outcome sentence's
                // "running" is no longer true — the lead-in is rewritten, but the
                // last measured position is still truth worth keeping.
                text =
                    if let blocksBehind, blocksBehind > 0 {
                        "The node was stopped from the app — last measured on \(chainName) at block \(height), \(blocksBehind) behind."
                    } else {
                        "The node was stopped from the app — last measured on \(chainName) at block \(height)."
                    }
            }
            if let gained = blocksSinceLastCheck {
                // One plural key covers all three counts — its catalog entry binds the
                // number so "zero" renders "No new blocks…", "one" the singular, and
                // "other" the plural — rather than a `block(s)` ternary only English
                // would survive.
                let gainedText: LocalizedStringResource =
                    "\(gained) new blocks since the last check."
                // A dedicated key, not the bare "%@ %@" a plain interpolation would
                // mint: a generic key is shared by any future pair of substituted
                // strings anywhere in the app, and a translator could never give this
                // join its own wording — including languages whose sentence join is
                // not a space.
                text = LocalizedStringResource(
                    "run.summary.with-gain",
                    defaultValue: "\(text) \(gainedText)",
                    comment: "Joins the run's status sentence to its blocks-gained sentence. The space is the sentence separator — adjust or replace for languages that join sentences differently.")
            }
            if let verdict = syncVerdict(syncEnding) {
                // The verdict comes last — the run's history before what it
                // concluded. Same dedicated-key join as `with-gain`, for the
                // same reason: the seam itself is a key translators own.
                text = LocalizedStringResource(
                    "run.summary.with-ending",
                    defaultValue: "\(text) \(verdict)",
                    comment: "Joins the run's summary so far to its sync-ending sentence. The space is the sentence separator — adjust or replace for languages that join sentences differently.")
            }
            return text
        }
    }

    /// The sentence a real sync ending appends — `nil` for `notMeasured`,
    /// which has nothing to add, and for `nodeStopped`, whose ending is
    /// carried by the rewritten lead-in instead.
    private static func syncVerdict(
        _ ending: SyncEnding
    ) -> LocalizedStringResource? {
        switch ending {
        case .notMeasured, .nodeStopped:
            return nil
        case .caughtUp:
            // A watch that saw the catch-up earned the ending; a gate that
            // found the node already there did not catch anything up.
            return "Caught up with the tip."
        case .alreadyAtTip:
            return "Already at the tip."
        case .stillSyncing:
            // The budget figure stays out: naming it invites a question the
            // sentence cannot answer, and "the run's time ran out" is honest.
            return "Still syncing — the run's time ran out."
        case let .noProgress(silentFor):
            // The silence the state measured, not a fixed phrase — a watch
            // that waited four minutes says so.
            if let silentFor {
                return "Made no progress for \(silentFor, format: summarySilenceFormat), so the watch ended."
            }
            return "Made no progress, so the watch ended."
        case let .conditionsChanged(refusal):
            guard let refusal else {
                // An unnamed condition still owes the frame: mid-watch a
                // drift ended the watch.
                return "Conditions changed, so the watch ended."
            }
            return conditionVerdict(refusal, watched: true)
        case let .watchRefused(refusal):
            guard let refusal else {
                // At the weigh-in nothing changed — the watch just never
                // began.
                return "Conditions did not allow the watch to start."
            }
            return conditionVerdict(refusal, watched: false)
        }
    }

    /// The appended sentence a `conditionsChanged` ending names — each refusal
    /// worded for the watch's own context (plan §3.6): `Refusal.message`'s
    /// "so the node did not start" is a lie here, since the node did start,
    /// is running, and is left running.
    ///
    /// `watched` picks the frame. A weigh-in refusal means the watch never
    /// began — the condition reads present-tense ("is metered") because it
    /// stands now. A mid-watch drift ended a watch that was running — the
    /// condition reads as an event ("turned metered"). Thermal wording stays
    /// level-agnostic: the weigh-in refuses at `.serious`, drift ends only
    /// at `.critical`, and "too warm" is true of both.
    private static func conditionVerdict(
        _ refusal: NodePreflight.Refusal, watched: Bool
    ) -> LocalizedStringResource {
        switch refusal {
        case .filesNotReadable:
            return watched
                ? "The node's files stopped being readable, so the watch ended."
                : "The node's files cannot be read, so the watch did not start."
        case .chainFolderMissing:
            return watched
                ? "There was nowhere left to write the chain data, so the watch ended."
                : "There is nowhere to write the chain data, so the watch did not start."
        case let .notEnoughDisk(freeBytes):
            // The same platform formatting `Refusal.message` uses, for the same
            // reason: the figure the device's storage screen shows, rendered in
            // the dialog's own locale.
            return watched
                ? "Only \(freeBytes, format: .byteCount(style: .file)) of free space was left, so the watch ended."
                : "Only \(freeBytes, format: .byteCount(style: .file)) of free space is left, so the watch did not start."
        case .meteredNetwork:
            return watched
                ? "The network turned metered, so the watch ended."
                : "The network is metered, so the watch did not start."
        case .dataRestrictedNetwork:
            return watched
                ? "Low Data Mode came on, so the watch ended."
                : "Low Data Mode is on, so the watch did not start."
        case .overheating:
            return watched
                ? "The device got too warm, so the watch ended."
                : "The device is too warm, so the watch did not start."
        case .lowPowerMode:
            return watched
                ? "Low Power Mode switched on, so the watch ended."
                : "Low Power Mode is on, so the watch did not start."
        }
    }

    /// The card's detail line while the watch runs — one composed line per
    /// state rather than two clauses competing for it (FR-003, plan §3.4).
    /// The position clause always shows; the caller supplies `silentFor`
    /// once the flat stretch is worth naming, and its presence both selects
    /// the line and supplies the duration — when silence becomes worth a
    /// clause is a leash decision, which stays out of the wording.
    ///
    /// A `LocalizedStringResource` like `summary(...)`: heights go in as raw
    /// integers so the resolver applies the locale's digit grouping at
    /// display time ("Block 843,210 of 915,000"), and the duration goes in
    /// typed so the platform renders it in the dialog's own locale ("last
    /// gain 3 min ago"). Seconds stay out of the unit set on purpose: the
    /// clause exists only past a two-minute silence, where a seconds figure
    /// would churn on every pass.
    static func watchDetail(
        height: Int, headers: Int, silentFor: Duration?
    ) -> LocalizedStringResource {
        if let silentFor {
            return "Block \(height) of \(headers), last gain \(silentFor, format: detailSilenceFormat) ago"
        }
        return "Block \(height) of \(headers)"
    }

    // MARK: - The watch-entry gate

    /// How old a tip may be before its age alone says the node is still
    /// syncing (~60 min, FR-001). A heuristic, not a Core rule — a few block
    /// intervals: generous enough that an ordinary lull between blocks rarely
    /// trips it on mainnet, short enough that a warm restart still enters the
    /// watch it belongs in (research §2). Provisional on the device pass
    /// (T039), like every 004 constant.
    static let tipFreshnessThreshold: Duration = .seconds(3_600)

    /// How a run's watch over a syncing node ended — the second axis of the
    /// run's report, as a plain value.
    ///
    /// The twin of the Shortcuts-facing `NodeSyncResult`, kept free of
    /// framework types so the decisions producing it can be tested on every
    /// platform. The two-way mapping lives on that type, so adding a case
    /// here will not compile until it is accounted for there.
    enum SyncResult: Equatable {
        /// The node reached the tip — the watch saw the catch-up happen, or
        /// the entry gate found it already there.
        case caughtUp
        /// The run's budget ran out with the node still behind.
        case stillSyncing
        /// Nothing advanced for long enough that the watch gave up — the
        /// node stopped answering, or the readings stayed flat past a leash.
        case noProgress
        /// The node was stopped from the app while the watch ran.
        case nodeStopped
        /// Device conditions refused the watch at the entry weigh-in or
        /// ended it mid-watch.
        case conditionsChanged
        /// The run has no sync answer to give: it declined before the
        /// weigh-in, got no answer before the watch, carried no watch
        /// budget, or found a self-defined chain — where "still syncing" is
        /// ill-defined, so nothing is claimed rather than something vacuous.
        case notMeasured
    }

    /// How the run's sync question was answered — the full ending, exactly
    /// once per run.
    ///
    /// The richer sibling of `SyncResult`: where the public axis collapses
    /// the two frames a watch-adjacent ending can arrive in, this one keeps
    /// them distinct — `caughtUp` (a watch saw the catch-up happen) versus
    /// `alreadyAtTip` (the entry gate found the node there, no watch ran),
    /// `conditionsChanged` (a condition ended a running watch) versus
    /// `watchRefused` (the entry weigh-in said no — the watch never began).
    /// The endings that need data carry it, so a combination that makes no
    /// sense — a silence on `caughtUp`, a condition on `stillSyncing` —
    /// cannot be constructed, and `watched` is derived rather than passed.
    enum SyncEnding: Equatable {
        /// The watch ran and saw the node reach the tip.
        case caughtUp
        /// The entry gate found the node already at the tip — no watch ran.
        case alreadyAtTip
        /// The run's budget ran out mid-watch with the node still behind.
        case stillSyncing
        /// Nothing advanced past a leash; carries the silence the state
        /// measured, `nil` when no measured duration exists.
        case noProgress(silentFor: Duration?)
        /// The node was stopped from the app while the watch ran.
        case nodeStopped
        /// A device condition ended a running watch — the refusal that
        /// caused it, `nil` when none is named.
        case conditionsChanged(NodePreflight.Refusal?)
        /// The entry weigh-in refused the watch — it never began.
        case watchRefused(NodePreflight.Refusal?)
        /// The run has no sync answer to give — see `SyncResult.notMeasured`.
        case notMeasured

        /// The ending on the public, Shortcuts-facing axis.
        ///
        /// The two frames of `caughtUp` and `conditionsChanged` collapse —
        /// the public report's six cases — while the internal value keeps
        /// them apart so the wording can say which actually happened.
        var result: SyncResult {
            switch self {
            case .caughtUp, .alreadyAtTip: .caughtUp
            case .stillSyncing: .stillSyncing
            case .noProgress: .noProgress
            case .nodeStopped: .nodeStopped
            case .conditionsChanged, .watchRefused: .conditionsChanged
            case .notMeasured: .notMeasured
            }
        }

        /// Whether the run's watch actually ran. Derived from the ending
        /// itself — never passed — so the card and the sentence can never
        /// disagree about whether a watch happened.
        var watched: Bool {
            switch self {
            case .caughtUp, .stillSyncing, .noProgress, .nodeStopped,
                 .conditionsChanged:
                true
            case .alreadyAtTip, .watchRefused, .notMeasured:
                false
            }
        }

        /// The honest reading of a bare public `SyncResult` — used only for
        /// a report that arrived without its ending (the `init()` path the
        /// AppIntents machinery takes), which should never happen. Where a
        /// non-watch variant exists the mapping picks it, so a fallthrough
        /// understates rather than claims a watch that did not run.
        init(collapsed result: SyncResult) {
            switch result {
            case .caughtUp: self = .alreadyAtTip
            case .stillSyncing: self = .stillSyncing
            case .noProgress: self = .noProgress(silentFor: nil)
            case .nodeStopped: self = .nodeStopped
            case .conditionsChanged: self = .watchRefused(nil)
            case .notMeasured: self = .notMeasured
            }
        }
    }

    /// Whether an outcome and a sync ending can truthfully coexist in one
    /// report.
    ///
    /// A real ending requires a run that measured a node: `.declined`,
    /// `.didNotComeUp` and `.noAnswer` each claim no measurement was made,
    /// which is false for any watch — a watch that stalls ends on the
    /// *measured* report it already had, never a blanked `.noAnswer`
    /// (FR-008, the plan's stop checklist). Enforced where the pair is
    /// committed (`NodeRunReport`'s init) and where the wording is
    /// produced, so the report's fields, the sentence and the card are
    /// guarded by the same rule.
    static func isCoherent(outcome: Outcome, ending: SyncEnding) -> Bool {
        switch outcome {
        case .started, .alreadyRunning:
            return true
        case .declined, .didNotComeUp, .noAnswer:
            return ending == .notMeasured
        }
    }

    /// What the first live reading says about the watch that could follow it.
    ///
    /// The gate answers not just whether the watch begins but — when it does
    /// not — which sync result the run reports instead, so a decline can
    /// never be divorced from its ending at the call site.
    enum WatchEntry: Equatable {
        /// The node reports itself still syncing on at least one of the
        /// three signals — the IBD flag set, a header gap open, or a tip
        /// older than the freshness threshold.
        case enter
        /// There is nothing to watch: the node was already at the tip, or
        /// the chain is a self-defined one the "still syncing" question is
        /// ill-defined on. The run reports the carried result without
        /// watching.
        case decline(SyncResult)
    }

    /// Whether a tip's own timestamp is recent enough to mean the node is at
    /// the tip — the "still syncing" signal that survives a warm restart,
    /// where the flag is already clear at chain-tip load and no header gap
    /// has been fetched yet.
    ///
    /// One function shared by the entry gate and the `caughtUp` proof's
    /// freshness leg (T012), so the two can never disagree about where
    /// "recent" ends. `tipTime` is miner-set and consensus-tolerant to ~2 h
    /// in the future — a negative age is fresh, never stale; the staleness
    /// such a skew can hide — research §2's ~1–3 h band — is this check's
    /// stated blind spot. A tip exactly at the threshold is fresh: *older
    /// than* is the stale direction.
    static func tipIsFresh(
        tipTime: Date, now: Date,
        within threshold: Duration = tipFreshnessThreshold
    ) -> Bool {
        now.timeIntervalSince(tipTime) <= threshold.timeInterval
    }

    /// The watch-entry gate (FR-001, FR-015): whether a run holding this
    /// first live reading begins watching — and when it does not, the sync
    /// result it reports instead.
    ///
    /// Three signals admit the watch because no one of them covers every
    /// still-syncing shape: the flag covers the never-synced or day-stale
    /// node but clears at chain-tip load for any tip under a day old; the
    /// gap covers a node that has fetched headers it lacks but reads zero
    /// until that fetch lands; the tip's age covers the warm restart both
    /// others miss (research §2).
    static func watchEntry(reading: LiveReading, now: Date) -> WatchEntry {
        // A self-defined chain is definitionally at its own tip — "still
        // syncing" is ill-defined on one, so nothing is claimed rather than
        // something vacuous. Checked first and absolutely: a just-started
        // regtest can sit with the flag set and still must not enter (FR-015).
        if BitcoinNetwork(rpcChain: reading.chain) == .regtest {
            return .decline(.notMeasured)
        }
        // The gap is judged on the node's own figures — `headers > blocks`,
        // not the derived `blocksBehind` — the same read `SyncWatchState`'s
        // undone-work test makes, so gate and watch can never disagree on
        // what a gap is.
        if reading.isInitialBlockDownload
            || reading.headers > reading.height
            || !tipIsFresh(tipTime: reading.tipTime, now: now) {
            return .enter
        }
        // Flag clear, gap closed, tip fresh is the `caughtUp` proof's bar
        // evaluated once at entry — the node was already at the tip when
        // the run arrived, which is an answer, not a missing measurement
        // (FR-005).
        return .decline(.caughtUp)
    }

    // MARK: - The entry weigh-in

    /// The one-time conditions check a run owes the paths that skipped
    /// preflight — `reportExistingNode` and `waitForStartingNode` — once the
    /// gate admits and before the watch commits (FR-012).
    ///
    /// Preflight's exemption — report or wait without weighing conditions —
    /// was written for a quick read: a run that read an answering node and
    /// left spent nothing the conditions guard. A run carrying a watch budget
    /// is different: committing means up to ~15 minutes of polling while the
    /// node keeps validating, so the weigh-in applies the same bar a start
    /// would face — `NodePreflight.refusal(for:)`, unchanged, order and
    /// thresholds alike — once, before the first watch pass. The unbudgeted
    /// path never reaches it (FR-014).
    ///
    /// Two conditions are deliberately not re-read: `filesReadable` and
    /// `chainFolderExists` are pinned satisfied because the weigh-in only ever
    /// runs while holding a live reading — a node answering RPCs has already
    /// proven it read the chain — so both are settled by position rather than
    /// measured again, and `prepareChainFolder()`'s filesystem write is never
    /// spent. The five facts that remain are the caller's to gather, actor-free:
    /// `freeDiskBytes` read directly, `thermalState` and `lowPowerModeEnabled`
    /// from `ProcessInfo`, and the network pair from
    /// `NetworkCostMonitor.first()` bounded at ~2 s — never `current`, which
    /// fails open exactly when the weigh-in runs, on a cold background launch
    /// before the first report lands (research §5). No `UIApplication` read —
    /// `isProtectedDataAvailable` is main-actor — which is what the deferred
    /// non-isolated `perform()` needs (plan §3.6).
    ///
    /// Every refusal maps to one ending: `conditionsChanged` naming the
    /// condition — never a `declined` report, since the node is already
    /// running and stays running, and "did not start" would be a lie (FR-005).
    /// Battery saver refuses here, exactly as preflight refuses a start under
    /// it — FR-011's "already on at entry is accepted" is `driftedCondition`'s
    /// delta rule for a committed watch, not an admission: a watch is minutes
    /// of sustained work the mode was switched on to avoid, and ending the run
    /// is the one step that relieves it — the app suspends, which freezes the
    /// in-process daemon.
    static func entryWeighIn(
        lowPowerModeEnabled: Bool,
        networkIsMetered: Bool,
        networkIsDataRestricted: Bool,
        thermalState: ProcessInfo.ThermalState,
        freeDiskBytes: Int64?,
        minimumFreeDiskBytes: Int64 = NodePreflight.minimumFreeDiskBytes
    ) -> NodePreflight.Refusal? {
        NodePreflight.refusal(
            for: .init(
                // Settled by position, not measured: a run only reaches the
                // weigh-in while holding the node's first answer.
                filesReadable: true, chainFolderExists: true,
                lowPowerModeEnabled: lowPowerModeEnabled,
                networkIsMetered: networkIsMetered,
                networkIsDataRestricted: networkIsDataRestricted,
                thermalState: thermalState,
                freeDiskBytes: freeDiskBytes),
            minimumFreeDiskBytes: minimumFreeDiskBytes)
    }

    // MARK: - The mid-watch drift check

    /// The device condition that ends a running watch this pass, if any —
    /// the drift half of the conditions pair `entryWeighIn` opens (FR-010,
    /// FR-011).
    ///
    /// The gather is deliberately narrower than the weigh-in's: the caller
    /// reads `NetworkCostMonitor.shared.current` — which never waits, and
    /// whose `.unknown` answer fails open as "not costly" — plus
    /// `thermalState` and `isLowPowerModeEnabled` off `ProcessInfo`, and
    /// nothing else. No `first()` wait, no filesystem write, no disk read:
    /// the once-per-run weigh-in can afford those, a ~180-pass watch cannot
    /// (research §5). Files and disk stay preflight-only past entry.
    ///
    /// Three rules, each shaped differently from the entry bar where the
    /// spec says so:
    ///
    /// - **Money conditions are absolute** — a metered link or Low Data
    ///   Mode spends something continuously and is consented to nowhere, so
    ///   either ends the run the pass it appears.
    /// - **Thermal trips only at `.critical`** — `.serious` is routine on a
    ///   phone that has been validating for minutes and ends nothing here;
    ///   the weigh-in's `.serious` refusal is the entry bar, not this one.
    /// - **Low Power Mode drifts only as a delta** — already on when the
    ///   watch committed is a standing preference, not a change: every
    ///   consent to the watch — preflight on the start path, the weigh-in
    ///   on the others — refuses the mode outright, so it only ever arrives
    ///   flipped on between that consent and the commit
    ///   (`SyncWatchState.lowPowerModeAtEntry` is the snapshot the delta is
    ///   measured against). Switched on mid-watch ends the run.
    ///
    /// The answer is the `Refusal` the ending names — `nil` keeps the watch
    /// running. When several hold on one pass, the reported one follows
    /// `refusal(for:)`'s relative order over the checked subset — money
    /// before heat before the power preference — so the named condition is
    /// the one that matters most.
    static func driftedCondition(
        network: NetworkCost,
        thermalState: ProcessInfo.ThermalState,
        lowPowerModeEnabled: Bool,
        lowPowerModeAtEntry: Bool
    ) -> NodePreflight.Refusal? {
        if network.isMetered { return .meteredNetwork }
        if network.isDataRestricted { return .dataRestrictedNetwork }
        if thermalState == .critical { return .overheating }
        if lowPowerModeEnabled && !lowPowerModeAtEntry { return .lowPowerMode }
        return nil
    }

    // MARK: - The sync watch's memory

    /// The most a watch tolerates with no fresh reading — or flat readings that
    /// still show undone work — before the run ends `noProgress` (~120 s,
    /// FR-007). Sits inside Core's own stall-recovery constants, so what peer
    /// churn can fix resolves inside it. Provisional on the device pass (T039).
    static let unproductiveLeash: Duration = .seconds(120)

    /// The most a watch tolerates flat readings with nothing provably left
    /// undone — an IBD node that has learned no gap yet, a chain quiet past
    /// Core's recency rule — before the run ends `noProgress` (~240 s, FR-007).
    /// Provisional on the device pass (T039).
    static let flatWindowLeash: Duration = .seconds(240)

    /// The sync watch's memory between polls — the heights it started from, the
    /// best it has seen, and how long it has been since the node showed work.
    ///
    /// A run holds one `var` for the length of a watch and hands each pass to
    /// `advance(instant:reading:)`: the pass's own instant and the node's
    /// answer, or `nil` when the question timed out or was declined. Time is
    /// measured pass to pass rather than against a since-last-gain timestamp —
    /// a first-ever start has never produced an advancing reading, so no
    /// timestamp can mark "last gain" for it — and a run the system suspended
    /// wakes to one large delta, the correct accounting since the in-process
    /// daemon froze for exactly as long.
    ///
    /// The two leashes implement FR-007. A pass feeds exactly one:
    ///
    /// - An *advancing* reading — `blocks` or `headers` above the best the
    ///   watch has seen — resets both and feeds none. Advancing headers count:
    ///   during header fetch the blocks are legitimately frozen while the gap
    ///   opens.
    /// - No fresh reading at all feeds `unproductive`.
    /// - A flat reading feeds `unproductive` only while undone work shows
    ///   (`headers > blocks`); everything else flat feeds `flatWindow`.
    ///
    /// Feeding one leash never resets the other: a quiet-chain flat stretch
    /// keeps counting toward `flatWindow` across the odd timed-out question,
    /// and silence keeps counting toward `unproductive` between flat answers.
    /// Only a gain resets — `stall` reports a tripped leash, unproductive
    /// first when both stand over.
    ///
    /// Peer evidence never enters: a `getpeerinfo` answer is `caughtUp`
    /// evidence only, not a chain reading (FR-007), so `advance` takes a
    /// `LiveReading?` and nothing else.
    ///
    /// Generic over the instant type alone — the state does arithmetic, never
    /// sleeps — so the run's `C: Clock<Duration>` and a `TestClock` hand it
    /// the same shape (`Instant.Duration == Duration`).
    struct SyncWatchState<Instant: InstantProtocol>: Equatable
        where Instant.Duration == Duration
    {
        /// One of the watch's two stall timers. Names the spec's leashes, so
        /// "this pass fed it" (`advance`'s return) and "it tripped" (`stall`)
        /// share one vocabulary.
        enum Leash: Equatable {
            /// No fresh reading, or a flat one with undone work still showing.
            case unproductive
            /// A flat reading with nothing provably left to do.
            case flatWindow
        }

        /// Where the watch started — the h₀ of the run's fraction and the
        /// baseline `blocksSince` measures "gained this run" against. A
        /// `TipBaseline`, not a `LiveReading`: a start position is not a
        /// measurement, and the reading's watch-only fields must not be
        /// readable back off one.
        let baseline: TipBaseline

        /// The headers height at entry — the bar `headersAdvanced` is judged
        /// against. `baseline` has no headers figure (a `TipBaseline` keeps
        /// only the two facts a delta needs), so the latch's reference lives
        /// here.
        let baselineHeaders: Int

        /// Low Power Mode as it read when the watch committed —
        /// `driftedCondition`'s baseline: already on at entry is a standing
        /// preference, so only a mid-watch switch-on ends the watch.
        let lowPowerModeAtEntry: Bool

        /// The bounds the leashes trip at — the spec figures by default,
        /// injectable so the action can wire the constants and tests can
        /// shrink them.
        let unproductiveLeash: Duration
        let flatWindowLeash: Duration

        /// The latest instant seen — deltas measure from here, not from
        /// entry, so one suspended pass lands as one large delta rather than
        /// being sliced by passes that never ran. A backwards pass feeds
        /// nothing and never moves the anchor.
        private var previousInstant: Instant

        /// The best block and header heights the watch has seen. "Advancing"
        /// is judged against these — never the last reading — so a rewound or
        /// reorged answer reads as flat rather than becoming a new low the
        /// next pass measures from.
        private(set) var bestBlocks: Int
        private(set) var bestHeaders: Int

        /// Time fed to each leash since the last advancing reading. Public to
        /// readers — the detail line's staleness clause ("last gain N ago")
        /// sums them — but only `advance` moves them.
        private(set) var unproductive: Duration
        private(set) var flatWindow: Duration

        /// Whether headers have moved past the entry figure — the leg the
        /// `caughtUp` proof needs on runs the tip-age gate let in, where flag
        /// and gap already described a finished state at the first answer and
        /// only observed growth proves the catch-up happened.
        var headersAdvanced: Bool { bestHeaders > baselineHeaders }

        /// A leash past its bound, if any — `.unproductive` wins when both
        /// stand over, since a node that stopped answering is the tighter
        /// signal.
        var stall: Leash? {
            if unproductive >= unproductiveLeash { return .unproductive }
            if flatWindow >= flatWindowLeash { return .flatWindow }
            return nil
        }

        init(
            at instant: Instant,
            entry reading: LiveReading,
            lowPowerMode: Bool,
            unproductiveLeash: Duration = NodeAutomation.unproductiveLeash,
            flatWindowLeash: Duration = NodeAutomation.flatWindowLeash
        ) {
            baseline = TipBaseline(chain: reading.chain, height: reading.height)
            baselineHeaders = reading.headers
            lowPowerModeAtEntry = lowPowerMode
            self.unproductiveLeash = unproductiveLeash
            self.flatWindowLeash = flatWindowLeash
            previousInstant = instant
            bestBlocks = reading.height
            bestHeaders = reading.headers
            unproductive = .zero
            flatWindow = .zero
        }

        /// Records one poll pass — its instant and the node's answer, or `nil`
        /// when none arrived — and returns the leash the pass fed, or `nil` on
        /// a gain. Exactly one leash is fed per pass; a gain resets both.
        @discardableResult
        mutating func advance(instant: Instant, reading: LiveReading?) -> Leash? {
            // A backwards instant feeds nothing and never re-anchors: storing
            // it would hand the rewound span to the next pass's delta.
            let delta = max(.zero, previousInstant.duration(to: instant))
            previousInstant = max(previousInstant, instant)
            if let reading {
                if reading.height > bestBlocks || reading.headers > bestHeaders {
                    bestBlocks = max(bestBlocks, reading.height)
                    bestHeaders = max(bestHeaders, reading.headers)
                    unproductive = .zero
                    flatWindow = .zero
                    return nil
                }
                // Undone work is the spec's `headers > blocks`, read off the
                // node's own figures rather than the derived `blocksBehind` —
                // a reading whose gap field ever disagreed could not misroute
                // the pass. Flat with nothing provably left is the longer
                // leash — the state cannot be expected to move faster.
                if reading.headers > reading.height {
                    unproductive += delta
                    return .unproductive
                }
                flatWindow += delta
                return .flatWindow
            }
            unproductive += delta
            return .unproductive
        }
    }

    // MARK: - The catch-up proof

    /// The fewest agreeing outbound block-serving peers the catch-up proof
    /// accepts as confirmation that nothing higher than our tip exists
    /// (FR-006). Two is the eclipse-aware floor: a run can be fooled into
    /// `caughtUp` only by peers as compromised as its own whole outbound view
    /// already is — the residual exposure every node carries. Provisional on
    /// the device pass (T039), like every 004 constant.
    static let peerConfirmationsRequired = 2

    /// How many of these peer answers count toward the catch-up proof at the
    /// node's current header height.
    ///
    /// An answer counts only when both halves hold: the connection is a
    /// self-initiated outbound block-serving kind — `outbound-full-relay` or
    /// `block-relay-only`, the only kinds a tip under a day old earns Core's
    /// anchored `getheaders` on — *and* its `synced_headers` equals `headers`
    /// exactly. Inbound peers never count (attacker-selected), nor manual,
    /// feeler, addr-fetch, or this fork's `private-broadcast`; an
    /// unclassifiable outbound resolves to no kind and fails closed. A peer
    /// announcing a different height — lower, or −1 for "announced nothing
    /// held" — proves nothing about this tip. Equality proves height, not
    /// block identity: a same-height fork satisfies it too, which is the
    /// question the proof asks.
    ///
    /// The count is exposed rather than folded into a `Bool` so the run can
    /// attribute a `noProgress` verdict — "one of two confirmed" and "zero
    /// answered" are different diagnoses on a device log.
    static func confirmingPeers(_ peers: [PeerEvidence], at headers: Int) -> Int {
        peers.filter {
            ($0.connectionType == .outboundFullRelay
                || $0.connectionType == .blockRelayOnly)
                && $0.syncedHeaders == headers
        }.count
    }

    /// Whether a flat pass has run out of ways to prove a catch-up except by
    /// asking the peers — the qualifier for the one `getpeerinfo` such a pass
    /// may spend (FR-006).
    ///
    /// Three conditions, all read off the current pass: the flag is clear
    /// (peers cannot certify past a set flag), the gap is closed (a node
    /// still behind its known headers has cheaper proof coming), and headers
    /// never advanced this run (a pass whose headers moved already has its
    /// leg). Tip staleness is deliberately absent — a fresh tip would already
    /// have ended the run on the freshness leg this same pass, so staleness
    /// is implied, and checking it again could only suppress an ask the pass
    /// was owed. Evaluated on flat passes; whether the pass was flat is the
    /// caller's knowledge — `SyncWatchState.advance` reports it.
    static func wantsPeerEvidence(reading: LiveReading, headersAdvanced: Bool) -> Bool {
        !reading.isInitialBlockDownload
            && reading.headers == reading.height
            && !headersAdvanced
    }

    /// Whether the node's own report proves the run saw it reach the tip —
    /// the `caughtUp` ending's one proof, re-evaluated on the current reading
    /// every pass (FR-006).
    ///
    /// Two preconditions gate everything, and no leg can substitute for
    /// either: the IBD flag cleared (Core's own verdict — reporting `caughtUp`
    /// while it stands would contradict the node, and peers cannot certify
    /// past it) and `blocks == headers` exactly — equality, not `≤`, so a
    /// nonsense `headers < blocks` reading fails closed rather than being
    /// read as "gap closed". Then one of three legs must hold:
    ///
    /// - `headersAdvanced` — headers moved past the entry figure this run:
    ///   the run watched a catch-up happen. Covers the tip-age-admitted node
    ///   that then fetched and closed its gap; the tip's age alone can stay
    ///   stale past it, since the last block to land may legitimately be old.
    /// - A fresh tip — `tipIsFresh` on the current reading, the same bar the
    ///   entry gate applies, so gate and proof can never disagree about where
    ///   "recent" ends. Covers blocks closing on already-known headers, where
    ///   the headers latch has nothing to set.
    /// - Confirming peers — on a pass where the first two legs cannot fire,
    ///   at least `requiredPeerConfirmations` outbound block-serving peers
    ///   report `synced_headers == headers`. The completed exchange Core
    ///   itself asked for, not an inference — the quiet-chain shape where
    ///   nothing new exists for headers to advance to.
    ///
    /// Absent and timed-out peer answers are indistinguishable and both
    /// right: an empty `peers` is simply no evidence.
    ///
    /// - Parameter requiredPeerConfirmations: the quorum — the spec's two by
    ///   default, injectable like the leash statics so the constant is wired
    ///   in one place.
    static func caughtUp(
        reading: LiveReading,
        headersAdvanced: Bool,
        peers: [PeerEvidence],
        now: Date,
        requiredPeerConfirmations: Int = peerConfirmationsRequired
    ) -> Bool {
        guard !reading.isInitialBlockDownload, reading.headers == reading.height else {
            return false
        }
        return headersAdvanced
            || tipIsFresh(tipTime: reading.tipTime, now: now)
            || confirmingPeers(peers, at: reading.headers) >= requiredPeerConfirmations
    }

    // MARK: - Ending precedence

    /// The one sync result the watch reports for this pass — or `nil` when
    /// no ending holds and the watch keeps going (FR-019).
    ///
    /// Each parameter is one candidacy, computed from the pass's own facts:
    /// the node was stopped from the app, the catch-up proof held, the drift
    /// check found a condition, a leash tripped, or the sync budget ran out.
    /// Overlaps are routine rather than rare — a tripped leash keeps
    /// standing until a gain resets it (`SyncWatchState.stall` reads
    /// accumulators, not edges), so a completed proof or a drifted
    /// condition can land on a pass where a leash is already over, and a
    /// deliberate stop can arrive on the pass a proof completes.
    ///
    /// The order is the contract, and each rank has its reason:
    ///
    /// - `nodeStopped` — a deliberate stop ends measurement itself; nothing
    ///   else the pass may have proven outranks the node's absence.
    /// - `caughtUp` — a completed proof is terminal truth: conditions that
    ///   drifted in the same pass are advisory for the next run, not a
    ///   verdict on one that already finished.
    /// - `conditionsChanged` — unconsented conditions outrank a tripwire.
    /// - `noProgress` — any verdict outranks a spent budget.
    /// - `stillSyncing` — the budget spent with nothing else to say.
    ///
    /// Two values are deliberately unanswerable here. `notMeasured` has no
    /// candidacy: a watch that committed already has its first answer, so
    /// "no answer" is not an ending it can reach. And cancellation is absent
    /// structurally — it ends the run, not the watch: the run's own checks
    /// (`Task.isCancelled`, and the flag the run's `onCancel` hook sets)
    /// live outside the candidacies, and a cancelled run is converted back
    /// into a thrown `CancellationError` at the action boundary rather than
    /// reported as a sync result.
    static func watchEnding(
        nodeStopped: Bool,
        caughtUp: Bool,
        conditionsChanged: Bool,
        noProgress: Bool,
        budgetSpent: Bool
    ) -> SyncResult? {
        if nodeStopped { return .nodeStopped }
        if caughtUp { return .caughtUp }
        if conditionsChanged { return .conditionsChanged }
        if noProgress { return .noProgress }
        if budgetSpent { return .stillSyncing }
        return nil
    }

    // MARK: - The bar's fraction and bands

    /// Where a budgeted run's start-up band ends — the first ~10% of the bar
    /// (FR-004).
    ///
    /// The watch shares one bar with the stages before it, and the bar never
    /// retreats: start-up writes reach ~0.9 and a completed reading writes
    /// the completion-equivalent value, so a sync fraction starting near
    /// zero would be silently discarded for the whole watch — a bar pinned
    /// near full while the node grinds. A budgeted run therefore compresses
    /// every pre-watch write into this band so the watch's own fraction has
    /// somewhere visible to start from.
    static let startUpBandEnd: Double = 0.1

    /// The bar's working ceiling — where the watch band ends (~95%, FR-004).
    ///
    /// The last ~5% is the reserve the honesty rules hold: a full bar claims
    /// the work finished, and only an earned `finish(_:)` is in a position
    /// to know that. Plan §3.4 assigns this figure as the meter's
    /// `advance(to:)` cap — a sync that lands with T032 if T038's device
    /// experiment keeps numeric writes. Today the meter stops one unit
    /// short of full; the agreement is specced, not yet coded.
    static let watchBandEnd: Double = 0.95

    /// The fraction of the distance to the live tip this run has closed —
    /// `(h − h₀) / max(liveHeaders − h₀, 1)` recomputed from each pass's
    /// own reading (FR-002). Never rate-projected, never clock-derived,
    /// never `verificationprogress`.
    ///
    /// The denominator is the pass's live `headers`, not the gap measured
    /// at entry: fresh headers arriving mid-watch grow it, which can pull
    /// the true fraction down — the display floor absorbs the dip while
    /// the detail line keeps reporting ground truth. A reorg below the
    /// entry height clamps the numerator at zero: the run closed nothing.
    /// And a node that has learned no gap yet — `liveHeaders` at or below
    /// the entry height — reads zero through the floored denominator
    /// rather than dividing by nothing.
    ///
    /// The arithmetic is reported raw: a reading whose height somehow
    /// passed its headers yields a fraction above one, which the band map
    /// clamps at the working ceiling. "More than everything known" is a
    /// display clamp, not a measurement the function should hide.
    static func syncFraction(height: Int, baselineHeight: Int, liveHeaders: Int) -> Double {
        Double(max(0, height - baselineHeight))
            / Double(max(liveHeaders - baselineHeight, 1))
    }

    /// The bar position a pre-watch write lands — its own 0–1 compressed
    /// into the start-up band (FR-004).
    ///
    /// Applied once around the run's progress callback, so every write a
    /// stage makes before the watch — the fixed milestones and the smooth
    /// first-answer ramp alike — lands inside `0 ... startUpBandEnd`
    /// without the call sites knowing the layout. An unbudgeted run never
    /// calls it: with no watch to leave room for, its writes keep the
    /// full bar.
    ///
    /// The input is clamped to `0...1`: a stray write lands at the band's
    /// edge rather than escaping it.
    static func startUpBand(_ stageFraction: Double) -> Double {
        min(max(stageFraction, 0), 1) * startUpBandEnd
    }

    /// The bar position a sync fraction lands during the watch — its 0–1
    /// swept across the watch band, from the start-up band's end up to
    /// the working ceiling (FR-002, FR-004).
    ///
    /// The floor is the start-up band's end, so the watch begins exactly
    /// where start-up left the bar: a fraction of zero parks the bar at
    /// the band floor — the honest display while the node has learned no
    /// gap yet — and a finished fraction stops at the ceiling, short of
    /// the full bar only an earned ending may fill.
    static func watchBand(_ distanceFraction: Double) -> Double {
        startUpBandEnd
            + min(max(distanceFraction, 0), 1) * (watchBandEnd - startUpBandEnd)
    }
}

/// `Duration`'s value as a `TimeInterval` — for comparing it against `Date`
/// arithmetic, which predates it.
private extension Duration {
    var timeInterval: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
