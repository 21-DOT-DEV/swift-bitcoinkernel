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
        /// Only a run that actually read a node finished the work the bar describes. A
        /// run that declined, or whose node never answered, did not — and filling the
        /// bar for those tells the person the opposite of what happened.
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

    /// Turns a finished run into what the card shows.
    ///
    /// Kept here, beside `summary(...)`, because it is a judgment about what the person
    /// is told — not display plumbing. The bar and the words are decided together so
    /// they cannot end up contradicting each other, which is the failure this replaced:
    /// the bar was previously filled for every ending, including runs that refused to
    /// start.
    static func ending(outcome: Outcome, summary: String) -> Ending {
        let title: String
        switch outcome {
        case .started: title = "Node running"
        case .alreadyRunning: title = "Node already running"
        case .didNotComeUp: title = "Node still starting"
        case .noAnswer: title = "Node did not answer"
        case .declined: title = "Node not started"
        }
        return Ending(
            fillsProgressBar: outcome == .started || outcome == .alreadyRunning,
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
    /// allowed, the other being `NodeSession.startTorIfStillEnabled()`'s.
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
        /// `startTorIfStillEnabled()`; the launch boundary reports the case
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
    }

    /// Reads the node's own chain summary, reusing the value types the on-screen
    /// dashboard already computes rather than re-deriving them.
    static func reading(from info: BlockchainInfo) -> LiveReading {
        let sync = SyncSummary(info)
        return LiveReading(chain: info.chain, height: sync.blocks, blocksBehind: sync.headersAhead)
    }

    /// Blocks between two readings — "since" whichever baseline the caller
    /// supplies — or `nil` when that cannot be known.
    ///
    /// The name promises no particular baseline: the run passes its pre-run
    /// snapshot, which is what makes the report's figure "blocks since the
    /// last check". `nil` when either reading is missing, or when the two are
    /// of **different chains** — subtracting a testnet height from a mainnet
    /// one would produce a confident-looking nonsense number. Never negative:
    /// a height that went backwards (a chain reorganisation, or a rebuilt
    /// index) is reported as no gain rather than a negative one.
    static func blocksSince(previous: LiveReading?, to current: LiveReading?) -> Int? {
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
    static func summary(
        outcome: Outcome,
        chain: String,
        height: Int,
        blocksBehind: Int?,
        blocksSinceLastCheck: Int?,
        declinedReason: LocalizedStringResource?
    ) -> LocalizedStringResource {
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
            guard let gained = blocksSinceLastCheck else { return headline }
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
            return LocalizedStringResource(
                "run.summary.with-gain",
                defaultValue: "\(headline) \(gainedText)",
                comment: "Joins the run's status sentence to its blocks-gained sentence. The space is the sentence separator — adjust or replace for languages that join sentences differently.")
        }
    }
}
