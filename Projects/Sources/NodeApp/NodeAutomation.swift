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

/// The decisions an unattended run makes, expressed as plain values.
///
/// Deliberately free of any Shortcuts or SwiftUI type, so they can be unit-tested
/// without a node, a screen, or the address-hiding network. Nothing calls these
/// yet — the background action that will is a later change — but they are the most
/// test-friendly part of the feature and their shape is already settled, so they
/// land here with the ownership groundwork. See
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
}
