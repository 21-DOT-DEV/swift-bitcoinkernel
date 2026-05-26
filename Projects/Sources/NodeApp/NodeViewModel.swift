//
//  NodeViewModel.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2022-present Timechain Software Initiative, Inc.
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

    /// `true` while Bitcoin Core reports `initialblockdownload`.
    /// Updated automatically every 30 seconds while the node is running.
    private(set) var isSyncing: Bool = false

    /// The `TorViewModel.sessionID` captured when the daemon was launched, if any.
    ///
    /// Views compare this against the current `TorViewModel.sessionID` to
    /// detect when Tor has restarted since launch (which invalidates the
    /// running daemon's `-proxy=` port) and surface a "restart required"
    /// hint. Cleared back to `nil` immediately on `stop()`.
    private(set) var launchedWithTorSession: UUID?

    /// SOCKS port captured at `start()` so the diagnostics layer can probe
    /// the same Tor listener at `before/after-node-stop` transitions.
    /// Cleared to `nil` on `stop()`.
    private var launchedWithTorSocksPort: UInt16?

    private let client = RPCClient(
        url: InternalRPC.url,
        cookieFile: InternalRPC.cookieFileURL
    )

    private var syncPollTask: Task<Void, Never>?

    /// Monotonically-increasing count of successful `start()` calls. Stamped
    /// into `NodeDiagnostics` tags so snapshots diff cleanly across cycles.
    private var startRunCounter = 0

    var isRunning: Bool { nodeState == .running }

    func start(arguments: [String], torSession: UUID? = nil, torSocksPort: UInt16? = nil) {
        guard nodeState == .stopped else { return }
        startRunCounter += 1
        let run = startRunCounter

        NodeDiagnostics.snapshot("before-node-start-\(run)")
        NodeDiagnostics.probeSocks5(port: torSocksPort, tag: "before-node-start-\(run)")

        nodeState = .starting
        launchedWithTorSession = torSession
        launchedWithTorSocksPort = torSocksPort

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
                startSyncPolling()
                NodeDiagnostics.snapshot("after-node-start-\(run)")
                NodeDiagnostics.probeSocks5(
                    port: self.launchedWithTorSocksPort,
                    tag: "after-node-start-\(run)"
                )
            }
        }
    }

    func stop() {
        guard nodeState == .running || nodeState == .starting else { return }
        let run = startRunCounter
        let socksPort = launchedWithTorSocksPort
        NodeDiagnostics.snapshot("before-node-stop-\(run)")
        NodeDiagnostics.probeSocks5(port: socksPort, tag: "before-node-stop-\(run)")
        nodeState = .stopping
        // Clear the captured Tor session reference at the start of teardown
        // so drift checks don't read a stale value during the .stopping window.
        launchedWithTorSession = nil
        launchedWithTorSocksPort = nil
        syncPollTask?.cancel()
        syncPollTask = nil
        isSyncing = false

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
            NodeDiagnostics.snapshot("after-node-stop-\(run)")
            NodeDiagnostics.probeSocks5(port: socksPort, tag: "after-node-stop-\(run)")
        }
    }

    // MARK: - IBD Polling

    private func startSyncPolling() {
        syncPollTask?.cancel()
        syncPollTask = Task {
            while !Task.isCancelled && nodeState == .running {
                await refreshSyncState()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func refreshSyncState() async {
        do {
            let info = try await client.getBlockchainInfo()
            guard !Task.isCancelled, nodeState == .running else { return }
            isSyncing = info.initialblockdownload
        } catch {
            nodeLogger.debug("Sync state poll failed: \(error.localizedDescription)")
        }
    }
}
