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

    /// On its way down or already there. Shutdown is one-way, so a `.stopping`
    /// node is no longer the running node an answer described — anything asking
    /// "is the node still up?" should treat it as stopped.
    var isStoppedOrStopping: Bool { self == .stopped || self == .stopping }
}

@MainActor @Observable
final class NodeViewModel {
    var nodeState: NodeState = .stopped

    /// `true` while Bitcoin Core reports `initialblockdownload`.
    /// Updated automatically every 30 seconds while the node is running.
    private(set) var isSyncing: Bool = false

    /// The most recent start failure surfaced to the UI, if any. Cleared on a
    /// fresh `start()` and when an RPC poll subsequently succeeds.
    private(set) var lastStartError: NodeError?

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

    /// Returns whether the start went ahead. `false` means the node was not
    /// `.stopped` — something else already moved it (another run, a tap on the
    /// app's Start button, a config change's restart) — and the call was a
    /// no-op. Callers that report what *they* did, as the unattended run does,
    /// need the refusal; the rest can ignore it.
    @discardableResult
    func start(arguments: [String], torSession: UUID? = nil, torSocksPort: UInt16? = nil) -> Bool {
        guard nodeState == .stopped else { return false }
        lastStartError = nil
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
                lastStartError = .rpcUnavailable
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
        return true
    }

    func stop() {
        Task { await performStop() }
    }

    /// Stops the daemon and returns only once `bitcoind_main()` has fully
    /// exited, so callers can sequence a clean restart (see
    /// ``applyAndRestart(arguments:torSession:torSocksPort:)``).
    func performStop() async {
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

        // Close the direct-RPC gate BEFORE triggering shutdown so concurrent
        // bitcoin_rpc() calls return NULL immediately instead of touching a
        // NodeContext that Shutdown() is tearing down. The HTTP "stop" RPC
        // still works — it goes through the HTTP server, not the direct bridge.
        bitcoin_rpc_reset()

        _ = try? await client.stop()

        // Wait for bitcoind_main() to return on a detached thread to avoid
        // blocking the main actor.
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

    /// Reconfigure-and-restart in place: stop the running daemon, wait for it
    /// to fully exit, then start it again with fresh `arguments`. No app
    /// relaunch — this drives a second in-process `bitcoind_main()` call, which
    /// the in-process-restart patches under `patches/` exist to make safe.
    func applyAndRestart(arguments: [String], torSession: UUID? = nil, torSocksPort: UInt16? = nil) async {
        guard nodeState == .running else { return }
        await performStop()
        start(arguments: arguments, torSession: torSession, torSocksPort: torSocksPort)
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
            lastStartError = nil
            Self.persistLastKnown(height: info.blocks, chain: info.chain)
        } catch {
            nodeLogger.debug("Sync state poll failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Resume state

    /// A tip persisted to either baseline store — height, chain, and when it
    /// was recorded. The type is deliberately store-neutral: `lastKnown` and
    /// `lastRun` both hand one back, and the caller's accessor says which —
    /// only the `last_known_*` store feeds the dashboard's pre-Start
    /// "resuming a known chain" line.
    struct PersistedTip: Equatable {
        let height: Int
        let chain: String
        let date: Date
    }

    /// Two baselines with two different owners — deliberately not one shared
    /// key set, because the two mean different things and a writer of one must
    /// never reset the other.
    ///
    /// `last_known_*` is **observational**: the last tip anyone saw. The sync
    /// poll writes it every 30 seconds while the node runs, and a run whose
    /// result is returned writes it too — a reported reading is a real
    /// observation. The dashboard's "last validated" line reads it.
    ///
    /// `last_run_*` is **transactional**: the last tip a run actually
    /// *reported*. Only the `.result` path at the intent boundary writes it,
    /// and only runs read it, as the `previous` a "blocks since last check"
    /// is measured from. If the poll wrote it, that delta would collapse
    /// toward zero whenever the app had been alive in the last half-minute —
    /// and a cancelled run would advance a baseline it never reported.
    private static let lastHeightKey = "last_known_height"
    private static let lastChainKey = "last_known_chain"
    private static let lastDateKey = "last_known_date"
    private static let lastRunHeightKey = "last_run_height"
    private static let lastRunChainKey = "last_run_chain"
    private static let lastRunDateKey = "last_run_date"

    /// The store is a parameter, defaulting to the app's real one, so tests can
    /// hand a throwaway suite instead — a test writing `.standard` would
    /// overwrite the person's real last-seen tip.
    static func persistLastKnown(
        height: Int, chain: String, in defaults: UserDefaults = .standard
    ) {
        persist(
            height: height, chain: chain, in: defaults,
            heightKey: lastHeightKey, chainKey: lastChainKey, dateKey: lastDateKey)
    }

    /// The observational baseline — the last tip anyone recorded, poll or
    /// returned run — or `nil` if nothing has ever been recorded.
    static func lastKnown(in defaults: UserDefaults = .standard) -> PersistedTip? {
        read(
            in: defaults,
            heightKey: lastHeightKey, chainKey: lastChainKey, dateKey: lastDateKey)
    }

    /// The run-owned counterparts — see the note on the keys above. No caller
    /// outside `NodeRun` has business writing these; the poll never touches
    /// them.
    static func persistLastRun(
        height: Int, chain: String, in defaults: UserDefaults = .standard
    ) {
        persist(
            height: height, chain: chain, in: defaults,
            heightKey: lastRunHeightKey, chainKey: lastRunChainKey, dateKey: lastRunDateKey)
    }

    /// The run-owned baseline — the last tip a returned result reported — or
    /// `nil` until the first result is returned after the split was introduced.
    static func lastRun(in defaults: UserDefaults = .standard) -> PersistedTip? {
        read(
            in: defaults,
            heightKey: lastRunHeightKey, chainKey: lastRunChainKey, dateKey: lastRunDateKey)
    }

    private static func persist(
        height: Int, chain: String, in defaults: UserDefaults,
        heightKey: String, chainKey: String, dateKey: String
    ) {
        defaults.set(height, forKey: heightKey)
        defaults.set(chain, forKey: chainKey)
        defaults.set(Date(), forKey: dateKey)
    }

    private static func read(
        in defaults: UserDefaults,
        heightKey: String, chainKey: String, dateKey: String
    ) -> PersistedTip? {
        guard defaults.object(forKey: heightKey) != nil,
              let chain = defaults.string(forKey: chainKey),
              let date = defaults.object(forKey: dateKey) as? Date
        else { return nil }
        return PersistedTip(
            height: defaults.integer(forKey: heightKey), chain: chain, date: date
        )
    }
}
