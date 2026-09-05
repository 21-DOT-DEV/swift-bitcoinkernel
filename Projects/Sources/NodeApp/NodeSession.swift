//
//  NodeSession.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

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

    /// Whether the node currently running was started by an unattended action rather
    /// than by someone using the app.
    ///
    /// An action shuts down only what it started; finding the node already running
    /// means reporting and leaving it alone, so an automation firing mid-session
    /// cannot stop a node someone is watching (ADR 0005).
    var startedByAutomation = false

    private init() {}
}
