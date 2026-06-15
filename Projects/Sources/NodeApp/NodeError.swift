//
//  NodeError.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// A start failure surfaced to the operator, with a recovery hint.
///
/// The embedded daemon does not return typed start errors to Swift — it logs
/// to `debug.log` and the RPC server simply never comes up — so this models
/// what the app can actually detect, and points recovery at the log viewer
/// where the daemon's own message (port in use, data dir locked, disk full)
/// is visible. New cases can be added as more failures become detectable.
enum NodeError: Error, Equatable, Identifiable {
    /// The RPC server did not answer after the daemon was started.
    case rpcUnavailable

    var id: String { String(describing: self) }

    var title: String {
        switch self {
        case .rpcUnavailable: "Node RPC Unavailable"
        }
    }

    var recovery: String {
        switch self {
        case .rpcUnavailable:
            """
            The node started but its RPC server never answered. Another instance \
            may hold the data directory or RPC port \(InternalRPC.port), or the disk \
            may be full. Open the Logs tab to read the daemon's output, then stop \
            and try again.
            """
        }
    }
}
