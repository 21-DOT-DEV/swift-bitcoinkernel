//
//  NodeAutomation.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

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

    /// How long a run holds the node open before starting to shut it down.
    ///
    /// A background-triggered action gets roughly 30 seconds in total. This is set
    /// below that deliberately, leaving room for the shutdown sequence, which sends a
    /// stop command and then waits for the daemon's main function to return
    /// (`Sources/Bitcoin/Daemon.swift:178`) rather than returning immediately.
    ///
    /// The action watches this clock itself rather than waiting to be told time is up
    /// (ADR 0007). The first release records what a real run achieves; this number is
    /// then tuned from that rather than from a guess.
    static let holdWindow: Duration = .seconds(18)

    /// Time reserved for shutting the node down after the hold ends.
    static let shutdownReserve: Duration = .seconds(7)
}
