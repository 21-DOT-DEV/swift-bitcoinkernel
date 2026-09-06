//
//  NodeSession.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Bitcoin
import Foundation

/// The node and privacy-network controllers, owned by the process rather than by a
/// screen.
///
/// They used to be created inside `ContentView`, which meant they existed only while
/// an interface did. When the system launches this app in the background to run a
/// Shortcuts action there is no interface, so nothing owned the node and the action
/// had nothing to start. See `Development/Specs/003-node-automation-action/plan.md`
/// §3.1.
///
/// This lives in the app rather than in `Sources/Shared` on purpose: the other demo
/// app will need something similar for its own action, but it owns a different thing
/// — a validation engine rather than a full daemon — so the shared version is better
/// designed once there are two real cases to design against.
@MainActor
final class NodeSession {
    static let shared = NodeSession()

    let node = NodeViewModel()
    let tor = TorViewModel(subsystem: "dev.21.NodeApp")

    /// A connection to the running daemon for reading its state.
    ///
    /// Owned here rather than created per run, because the action's defining property
    /// is that it runs when no screen exists. It is typed as the reading seam the app
    /// already defines for this, so the logic that consumes it can be tested against a
    /// fake (`Projects/Sources/NodeApp/Dashboard.swift:20`).
    let reader: any DashboardDataSource = RPCClient(
        url: InternalRPC.url, cookieFile: InternalRPC.cookieFileURL
    )

    /// Whether an unattended run currently holds this session.
    ///
    /// An action shuts down only what it started; finding the node already running
    /// means reporting and leaving it alone, so an automation firing mid-session
    /// cannot stop a node someone is watching (ADR 0005).
    private(set) var startedByAutomation = false

    /// Claims the session for an unattended run, or refuses if one already holds it.
    ///
    /// Checked and set together with no waiting in between, so two runs triggered
    /// close together cannot both believe they own the node.
    func claimForAutomation() -> Bool {
        guard !startedByAutomation else { return false }
        startedByAutomation = true
        return true
    }

    func releaseAutomation() { startedByAutomation = false }

    private init() {}
}
