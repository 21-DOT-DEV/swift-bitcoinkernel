//
//  DaemonConfig.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Bitcoin
import Foundation

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
}
