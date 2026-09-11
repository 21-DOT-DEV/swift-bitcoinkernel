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

/// The node controller and the address-hiding-network (Tor) controller, owned by
/// the process rather than by a screen.
///
/// They used to be created inside `ContentView`, so they existed only while an
/// interface did. A Shortcuts action launched in the background has no interface,
/// so nothing would own them and the action would have nothing to reach. Owning
/// them here means the same objects are available whether or not a window is on
/// screen.
///
/// This is what the Shortcuts actions reach through when they run with no window on
/// screen. See `Development/Specs/003-node-automation-action/plan.md` §3.2 and
/// ADR 0005.
@MainActor
final class NodeSession {
    static let shared = NodeSession()

    let node = NodeViewModel()
    let tor = TorViewModel(subsystem: "dev.21.NodeApp")

    /// A connection for asking the running node questions — which chain it is on, what
    /// block height it has reached, how many peers it has.
    ///
    /// Owned here rather than created per run, because an action's defining property is
    /// that it runs when no window exists. Without this the action can start the node
    /// but cannot learn whether it came up or what it reached, so it has nothing to
    /// report. The app's own screens each build their own connection; this is the one
    /// an action uses.
    ///
    /// Typed as the read-only interface the app already defines (`DashboardDataSource`
    /// in `Dashboard.swift`) rather than the concrete client, so a test can hand in a
    /// stand-in and exercise the reporting logic without a live node.
    let reader: any DashboardDataSource = RPCClient(
        url: InternalRPC.url, cookieFile: InternalRPC.cookieFileURL
    )

    private init() {}
}
