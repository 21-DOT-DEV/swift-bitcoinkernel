//
//  DaemonConfig.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2022-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Bitcoin
import Foundation
import os.log

private let configLogger = Logger(subsystem: "dev.21.NodeApp", category: "DaemonConfig")

/// Builds Bitcoin Core daemon arguments from current user configuration.
///
/// Uses the type-safe `BitcoinConfig` builder from the Bitcoin library
/// to produce validated CLI argument lists.
enum DaemonConfig {

    /// Build daemon arguments from current configuration stored in UserDefaults.
    ///
    /// - Parameter torProxy: The SOCKS proxy address in `"host:port"` format,
    ///   provided by `TorViewModel.proxyAddress` when Tor is running.
    ///   When `nil` and Tor is enabled, the proxy argument is omitted
    ///   (Tor not yet bootstrapped).
    static func buildArguments(torProxy: String? = nil) -> [String] {
        // Not fatal here — a caller with a screen in front of it will see the daemon
        // fail on its own — but never silent either. A failure means there is nowhere
        // to write, and the error carries which of the many reasons it was. An
        // unattended run does not rely on this: it prepares the folder itself first and
        // declines outright if it cannot, because nobody is there to read a log.
        do {
            try prepareDataDirectory(at: dataDirectory)
        } catch {
            configLogger.error(
                "Data directory could not be prepared: \(error.localizedDescription, privacy: .public)"
            )
        }
        let defaults = UserDefaults.standard
        let network = BitcoinNetwork(
            rawValue: defaults.string(forKey: "bitcoin_network") ?? ""
        ) ?? .mainnet

        return switch network {
        case .mainnet: configure(.mainnet(), defaults: defaults, torProxy: torProxy)
        case .testnet: configure(.testnet(), defaults: defaults, torProxy: torProxy)
        case .signet:  configure(.signet(), defaults: defaults, torProxy: torProxy)
        case .regtest: configure(.regtest(), defaults: defaults, torProxy: torProxy)
        }
    }

    // MARK: - Private

    private static func configure<N>(
        _ base: BitcoinConfig<N>, defaults: UserDefaults, torProxy: String?
    ) -> [String] {
        var config = base
            .server()
            .rpcBind(.localhost)
            .rpcAllowIP(.localhost)
            .rpcPort(InternalRPC.port)
            .rpcCookieFile(InternalRPC.cookieFileURL.path)
            .dataDir(dataDirectory.path(percentEncoded: false))

        // Node type
        let nodeType = NodeType(
            rawValue: defaults.string(forKey: "node_type") ?? ""
        ) ?? .pruned
        switch nodeType {
        case .pruned:
            let mb = defaults.double(forKey: "prune_size_mb")
            config = config.prune(.size(mb: UInt(mb > 0 ? mb : 550)))
        case .archival:
            break
        case .compactFilters:
            config = config.blockFilterIndex(.all).peerBlockFilters()
        }

        // Privacy — proxy comes from TorViewModel's live SOCKS endpoint
        let torEnabled = defaults.bool(forKey: "tor_enabled")
        if torEnabled, let proxy = torProxy {
            config = config.proxy(proxy)
        }

        // -privatebroadcast requires Tor/I2P reachability per Bitcoin Core docs.
        // Gate on both the user preference AND a live proxy so a stale persisted
        // pref can't leak when Tor has been toggled off.
        if torEnabled, torProxy != nil, defaults.bool(forKey: "private_broadcast_enabled") {
            config = config.privateBroadcast()
        }

        // Resources
        let mempool = defaults.double(forKey: "max_mempool_mb")
        config = config.maxMempool(UInt(mempool > 0 ? mempool : 300))

        let conns = defaults.double(forKey: "max_connections")
        config = config.maxConnections(UInt(conns > 0 ? conns : 125))

        if let listen = defaults.object(forKey: "listen_enabled") as? Bool, !listen {
            config = config.listen(false)
        }

        // RPC authentication
        let rpcAuth = defaults.string(forKey: "rpc_auth") ?? ""
        if let auth = RPCAuth(rawString: rpcAuth) {
            config = config.rpcAuth(auth)
        }

        return config.arguments
    }

    // MARK: - Data directory

    /// The app's data directory under Application Support. Bitcoin Core adds
    /// the per-network subdirectory itself (given `-signet`/`-testnet`/`-regtest`),
    /// so all networks coexist under here without mixing chainstate.
    static var dataDirectory: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        )) ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("NodeApp", isDirectory: true)
    }

    /// Creates `url` if needed and asks the system to keep it out of device backups —
    /// chainstate is reproducible from the network and does not belong in
    /// iCloud or local device backups.
    ///
    /// **Only the folder's absence throws.** The two failures are not equivalent and
    /// are no longer treated as one. Without the folder there is nowhere to write and
    /// nothing can proceed. Without the backup mark the folder is there and perfectly
    /// writable — the node runs fine, and the only cost is that backups may grow. So
    /// the mark is best-effort and logged (see `excludeFromBackups(_:)`), and a caller
    /// deciding whether a run may start weighs only the folder.
    @discardableResult
    static func prepareDataDirectory(at url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        excludeFromBackups(url)
        return url
    }

    /// Asks the system to leave `url` out of iCloud and device backups, reporting
    /// nothing and throwing nothing.
    ///
    /// Three things about this flag shape the code. It is **advisory** — Apple
    /// documents it as guidance about what the system *can* exclude, not a guarantee
    /// that the data never appears in a backup — so refusing to run because it could
    /// not be set would be refusing on the strength of a promise that does not exist.
    /// It can be **silently reset** by later file operations, and the documented
    /// recovery is simply to set it again, which happens because every run prepares
    /// the folder. And it applies to a **whole directory**, whose contents inherit it,
    /// which is why it is set here once on the folder rather than on each of the
    /// thousands of files the node writes inside it.
    ///
    /// Read before writing, so the common case touches nothing: re-setting a flag that
    /// is already set is a filesystem write on every single run for no effect.
    static func excludeFromBackups(_ url: URL) {
        do {
            let current = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
            guard current.isExcludedFromBackup != true else { return }
            var mutable = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try mutable.setResourceValues(values)
        } catch {
            // Left running on purpose. Logged rather than swallowed because the error
            // names the cause, and this is the only trace anyone gets — on an
            // unattended run there is no screen to show it on.
            configLogger.error(
                "Chain folder could not be marked as excluded from backups, so backups may grow: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
