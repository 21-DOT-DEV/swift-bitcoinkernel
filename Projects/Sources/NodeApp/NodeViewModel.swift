//
//  NodeViewModel.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Bitcoin
import bitcoind
import Foundation
import Observation
import os.log

private let nodeLogger = Logger(subsystem: "dev.21.NodeApp", category: "Node")

enum NodeState: String, Sendable {
    case stopped = "Stopped"
    case starting = "Starting"
    case running = "Running"
    case stopping = "Stopping"
}

@MainActor @Observable
final class NodeViewModel {
    var nodeState: NodeState = .stopped

    private let client = RPCClient(
        url: InternalRPC.url,
        cookieFile: InternalRPC.cookieFileURL
    )

    var isRunning: Bool { nodeState == .running }

    func start(arguments: [String]) {
        guard nodeState == .stopped else { return }
        nodeState = .starting

        Daemon.start(arguments)

        // Daemon.start() returns immediately. Bootstrap the direct RPC
        // bridge (which polls until the RPC server responds), then
        // transition to .running.
        Task {
            do {
                try await Daemon.bootstrap(
                    cookieFile: InternalRPC.cookieFileURL,
                    port: InternalRPC.port
                )
                nodeLogger.info("Direct RPC bridge bootstrapped")
            } catch {
                nodeLogger.warning("Bridge bootstrap failed: \(error.localizedDescription) — HTTP fallback active")
            }
            // Guard against a stop() that raced ahead of us.
            if nodeState == .starting {
                nodeState = .running
            }
        }
    }

    func stop() {
        guard nodeState == .running || nodeState == .starting else { return }
        nodeState = .stopping

        // Use the HTTP RPC "stop" command — this triggers Bitcoin Core's
        // internal Shutdown() without a process signal, safe on all platforms.
        // Task inherits @MainActor isolation (Swift 6 best practice).
        // Blocking work is offloaded via Thread.detachNewThread.
        Task {
            // Close the direct-RPC gate BEFORE triggering shutdown so
            // concurrent bitcoin_rpc() calls return NULL immediately
            // instead of touching a NodeContext that Shutdown() is
            // tearing down. The HTTP "stop" RPC still works because
            // it goes through the HTTP server, not the direct bridge.
            bitcoin_rpc_reset()

            _ = try? await client.stop()

            // Wait for bitcoind_main() to return on a detached thread
            // to avoid blocking the main actor.
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                Thread.detachNewThread {
                    Daemon.waitUntilStopped()
                    continuation.resume()
                }
            }

            nodeState = .stopped
        }
    }
}
