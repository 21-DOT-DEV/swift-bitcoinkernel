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
/// without a node, a screen, or the address-hiding network. The run that will call
/// them is a later change; it orchestrates and does no deciding — every judgment
/// it appears to make is one of these. See
/// `Development/Specs/003-node-automation-action/plan.md` §3 and §7.
enum NodeAutomation {

    /// What an unattended run should do next.
    enum Step: Equatable {
        /// A node is already running, so report on it and change nothing. An
        /// automation must never interrupt a node someone started themselves
        /// (ADR 0005).
        case reportExistingNode
        /// The privacy setting is on but the network is not established yet; spend
        /// the window establishing it rather than starting the node.
        case waitForPrivateNetwork
        /// Nothing in the way; start the node.
        case startNode
    }

    /// Decides the next step from three plain facts.
    static func step(nodeIsStopped: Bool, privacyEnabled: Bool, privacyReady: Bool) -> Step {
        guard nodeIsStopped else { return .reportExistingNode }
        if privacyEnabled && !privacyReady { return .waitForPrivateNetwork }
        return .startNode
    }

    /// Whether an answer that has just arrived from the node may still be reported.
    ///
    /// The channel used to question the node cannot be interrupted once a question is
    /// in flight: underneath it is a plain synchronous call that runs to completion and
    /// hands back an answer regardless of what happened while it was away. Two things
    /// can happen in that window. The run can be called off — the person taps stop on
    /// the progress card, or the system runs out of patience. Or the node can be shut
    /// down from inside the app by someone who opened it mid-wait.
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
    static let inProgressTitle = "Starting Bitcoin node"

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
        case .declined: title = "Node not started"
        }
        return Ending(
            fillsProgressBar: outcome == .started || outcome == .alreadyRunning,
            title: title,
            detail: summary)
    }

    /// Raised when a run is asked to start while the privacy network is on but no
    /// proxy address exists.
    enum StartRefusal: Error, Equatable {
        case privateNetworkNotReady
    }

    /// Builds the daemon's launch arguments, refusing outright when the privacy
    /// setting is on and no *usable* proxy address exists — treating `nil`, an empty
    /// string, and a whitespace-only string all as "not ready".
    ///
    /// The shared argument builder adds the proxy only when the address is non-`nil`,
    /// so a non-`nil` empty string slips past as if it were a real proxy and starts
    /// the node with a blank proxy setting — that is, on a direct connection, sending
    /// the person's home network address to peers after they asked it not to. Refusing
    /// only `nil` would leave that hole open, so this is a privacy floor: anything that
    /// is not a real address is refused. (The policy is recorded in the plan §7 and
    /// becomes its own decision record when the background action wires this in.)
    ///
    /// The value forwarded to the builder is the trimmed one, so surrounding
    /// whitespace never reaches the daemon as part of a `-proxy=` argument.
    ///
    /// - Parameter build: the shared argument builder, taking a proxy address.
    static func startArguments(
        privacyEnabled: Bool,
        proxyAddress: String?,
        build: (String?) -> [String]
    ) throws -> [String] {
        let trimmedProxy = proxyAddress?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasUsableProxy = !(trimmedProxy?.isEmpty ?? true)
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

    /// Blocks gained between two readings, or `nil` when that cannot be known.
    ///
    /// `nil` when either reading is missing, or when the two are of **different
    /// chains** — subtracting a testnet height from a mainnet one would produce a
    /// confident-looking nonsense number. Never negative: a height that went backwards
    /// (a chain reorganisation, or a rebuilt index) is reported as no gain rather than
    /// a negative one.
    static func blocksGained(from start: LiveReading?, to end: LiveReading?) -> Int? {
        guard let start, let end, start.chain == end.chain else { return nil }
        return max(0, end.height - start.height)
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
    }

    /// The single sentence a person reads or hears, derived from the same values the
    /// named fields carry so the two can never disagree.
    ///
    /// The numbers go through `formatted()` — the locale-aware style the dashboard
    /// already uses — so a height reads "900,000" rather than "900000" on a device set
    /// to a language that groups digits.
    static func summary(
        outcome: Outcome,
        chain: String,
        height: Int,
        blocksBehind: Int?,
        blocksSinceLastCheck: Int?,
        declinedReason: String?
    ) -> String {
        switch outcome {
        case .declined:
            // The reason is the whole message: it is the only thing that tells the
            // person what to change.
            return declinedReason ?? "The node did not start."
        case .didNotComeUp:
            return "The node was started but had not come up yet, so nothing was measured."
        case .alreadyRunning, .started:
            let verb = outcome == .started ? "Node running" : "A node was already running"
            var sentence = "\(verb) on \(chain) at block \(height.formatted())"
            if let blocksBehind, blocksBehind > 0 {
                sentence += ", \(blocksBehind.formatted()) behind"
            }
            sentence += "."
            if let gained = blocksSinceLastCheck {
                sentence +=
                    gained == 0
                    ? " No new blocks since the last check."
                    : " \(gained.formatted()) new block\(gained == 1 ? "" : "s") since the last check."
            }
            return sentence
        }
    }
}
