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

/// The decisions an unattended run makes, as plain values.
///
/// Kept free of any Shortcuts or SwiftUI type so they can be tested without a node,
/// a screen, or a privacy network. See
/// `Development/Specs/003-node-automation-action/plan.md` §3.2.
enum NodeAutomation {

    /// What an unattended run should do next.
    enum Step: Equatable {
        /// The node is not stopped, so report on it and change nothing. An action
        /// shuts down only what it started (ADR 0005), which is what stops an
        /// automation interrupting a session someone is watching.
        case reportExistingNode
        /// The privacy setting is on and the network is not established yet. The run
        /// spends its window establishing it, leaving the cache warm for next time.
        case waitForPrivateNetwork
        /// Nothing in the way; start the node.
        case startNode
    }

    static func step(nodeIsStopped: Bool, privacyEnabled: Bool, privacyReady: Bool) -> Step {
        guard nodeIsStopped else { return .reportExistingNode }
        if privacyEnabled && !privacyReady { return .waitForPrivateNetwork }
        return .startNode
    }

    enum StartRefusal: Error, Equatable {
        /// The privacy setting is on but no proxy address exists.
        case privateNetworkNotReady
    }

    /// Builds the daemon's arguments, refusing outright when the privacy setting is
    /// on and no proxy address exists.
    ///
    /// This check belongs to unattended runs alone. The shared builder omits the
    /// proxy argument when no address is present, which is fine with someone
    /// watching the screen but would start the node on a direct connection
    /// unattended, exposing the person's home network address to peers — forbidden by
    /// ADR 0006. Relying on the wait in `step(...)` having succeeded is not enough: a
    /// wait that exits for any reason would fall straight through into an
    /// unprotected start.
    ///
    /// - Parameter build: the shared argument builder, taking a proxy address.
    static func startArguments(
        privacyEnabled: Bool,
        proxyAddress: String?,
        build: (String?) -> [String]
    ) throws -> [String] {
        if privacyEnabled && proxyAddress == nil { throw StartRefusal.privateNetworkNotReady }
        return build(proxyAddress)
    }

    /// Everything the action may take, end to end.
    ///
    /// Measured, not published. Two device runs logged the system's out-of-time
    /// warning at 27.4 and 27.9 seconds after the run began, and both finished about
    /// a third of a second after it. The widely cited 30 seconds is therefore too
    /// generous by roughly three, which is why runs were landing late.
    static let budget: Duration = .seconds(27)

    /// Held back for shutting the node down.
    ///
    /// Measured at 4.5 seconds on device, rounded up. Shutdown sends a stop command
    /// and then waits for the daemon's main function to return
    /// (`Sources/Bitcoin/Daemon.swift:178`), so it is not instant and cannot be
    /// started at the limit.
    static let shutdownReserve: Duration = .seconds(6)

    /// The instant work must stop so shutting down still fits inside the budget.
    ///
    /// The action watches this itself rather than waiting to be told time is up
    /// (ADR 0007), because shutdown cannot be interrupted once begun and cannot be
    /// begun by a signal the action is blocked from receiving.
    static func workDeadline(from start: ContinuousClock.Instant) -> ContinuousClock.Instant {
        start.advanced(by: budget - shutdownReserve)
    }

    /// How long the node was genuinely running, which is the only interval in which
    /// blocks can be gained.
    ///
    /// Reported separately from the action's total because startup produces no
    /// blocks: without this, "the height moved by N" cannot be told apart from "the
    /// node barely got going".
    static func secondsRunning(
        readyAt: ContinuousClock.Instant, stoppedAt: ContinuousClock.Instant
    ) -> Double {
        max(0, Double(readyAt.duration(to: stoppedAt) / .milliseconds(1)) / 1000)
    }

    /// The figures the report needs, all from one reading so they cannot disagree.
    struct LiveReading: Equatable {
        let chain: String
        let height: Int
        /// Headers known but not yet downloaded as full blocks. Without this a height
        /// reads as "caught up" when the node may be far behind.
        let blocksBehind: Int
    }

    /// Whether a run should ask the node to stop.
    ///
    /// Two conditions, and both must hold.
    ///
    /// The person has to have asked for it. The action's own time is capped at about
    /// 27 seconds, but the node it starts keeps running long after the action returns
    /// — measured between 8 and 15 minutes — and that is when blocks actually arrive.
    /// Stopping at the end of the action discarded all of it, so leaving the node
    /// running is the default and stopping is opt-in.
    ///
    /// And only a node that answered at least once. One that never did is still inside
    /// its own start-up, where a stop request cannot be serviced, and the wait for
    /// it cannot be interrupted (ADR 0007) — so asking blocks until the system kills
    /// the run. A device run on a locked phone took 121 s to load its block index,
    /// hit this path, and was reported to the person as a timeout.
    static func shouldRequestShutdown(nodeAnswered: Bool, askedToStop: Bool) -> Bool {
        nodeAnswered && askedToStop
    }

    /// Whether shutting down took longer than the time held back for it.
    ///
    /// Four device runs took 0.34, 2.07, 3.81 and 5.10 s against a 6 s reserve —
    /// climbing, most likely with the amount of freshly-synced state to write out.
    /// Four samples cannot say whether that levels off, so the reserve stays fixed
    /// and each run reports its own overrun rather than the number being guessed.
    static func shutdownOverran(_ took: Duration) -> Bool { took > shutdownReserve }


    /// Blocks gained between the start and end of a run.
    ///
    /// Measured directly rather than inferred by comparing one run against the
    /// previous one, which breaks if a run is missed or arrives out of order.
    static func blocksGained(from start: LiveReading?, to end: LiveReading?) -> Int? {
        guard let start, let end, start.chain == end.chain else { return nil }
        return max(0, end.height - start.height)
    }

    /// Builds the reading from the daemon's own chain summary, reusing the value
    /// types the on-screen dashboard already computes rather than re-deriving them.
    static func reading(from info: BlockchainInfo) -> LiveReading {
        let sync = SyncSummary(info)
        return LiveReading(chain: info.chain, height: sync.blocks, blocksBehind: sync.headersAhead)
    }
}
