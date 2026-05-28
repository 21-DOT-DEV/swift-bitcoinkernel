//
//  BitcoinConfig+Presets.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

// MARK: - Mainnet Presets

extension BitcoinConfig where N == Mainnet {

    /// A pruned mainnet node with block filters and RPC server enabled.
    ///
    /// Suitable as a starting point for most production setups.
    ///
    /// - Parameter rpcAuth: Credentials for RPC authentication.
    public static func prunedDefault(rpcAuth: RPCAuth) -> Self {
        mainnet()
            .server()
            .rpcBind(.allInterfaces)
            .rpcAllowIP(.localhost)
            .rpcPort(Mainnet.defaultRPCPort)
            .rpcAuth(rpcAuth)
            .prune(.minimum)
            .blockFilterIndex(.all)
    }

    /// A full (non-pruned) mainnet node with transaction index.
    ///
    /// Suitable for block explorers and services that query historical
    /// transactions.
    ///
    /// - Parameter rpcAuth: Credentials for RPC authentication.
    public static func fullNode(rpcAuth: RPCAuth) -> Self {
        mainnet()
            .server()
            .txIndex()
            .rpcAuth(rpcAuth)
            .dbCache(4000)
    }
}

// MARK: - Regtest Preset

extension BitcoinConfig where N == Regtest {

    /// A regtest node bound to localhost, suitable for development and testing.
    ///
    /// - Parameter rpcAuth: Credentials for RPC authentication.
    public static func regtestDefault(rpcAuth: RPCAuth) -> Self {
        regtest()
            .server()
            .rpcBind(.localhost)
            .rpcAllowIP(.localhost)
            .rpcPort(Regtest.defaultRPCPort)
            .rpcAuth(rpcAuth)
    }
}

// MARK: - Phase 2 Mainnet Presets

extension BitcoinConfig where N == Mainnet {

    /// A bandwidth-constrained node, suitable for metered connections.
    ///
    /// Limits outbound data, disables DNS seeding, and reduces connection count.
    ///
    /// - Parameter rpcAuth: Credentials for RPC authentication.
    public static func lowBandwidth(rpcAuth: RPCAuth) -> Self {
        mainnet()
            .server()
            .rpcBind(.localhost)
            .rpcAllowIP(.localhost)
            .rpcAuth(rpcAuth)
            .prune(.minimum)
            .maxConnections(8)
            .maxUploadTarget(500)
            .dnsSeed(false)
    }

    /// A node routing all traffic through Tor for privacy.
    ///
    /// Sets the SOCKS5 proxy and restricts networking to onion peers only.
    ///
    /// - Parameter rpcAuth: Credentials for RPC authentication.
    public static func torNode(rpcAuth: RPCAuth) -> Self {
        mainnet()
            .server()
            .rpcBind(.localhost)
            .rpcAllowIP(.localhost)
            .rpcAuth(rpcAuth)
            .proxy("127.0.0.1:9050")
            .onion("127.0.0.1:9050")
            .onlyNet(.onion)
            .listen(false)
            .prune(.minimum)
    }

    /// A resource-constrained node tuned for single-board computers (e.g. Raspberry Pi).
    ///
    /// Reduces memory usage, limits connections, and prunes to minimum.
    ///
    /// - Parameter rpcAuth: Credentials for RPC authentication.
    public static func raspberryPi(rpcAuth: RPCAuth) -> Self {
        mainnet()
            .server()
            .rpcBind(.localhost)
            .rpcAllowIP(.localhost)
            .rpcAuth(rpcAuth)
            .prune(.minimum)
            .dbCache(150)
            .maxConnections(40)
            .maxMempool(50)
            .par(1)
    }

    /// A node tuned for use with the Eclair Lightning Network daemon.
    ///
    /// Enables `txindex` and configures RPC for Eclair's requirements.
    ///
    /// - Parameter rpcAuth: Credentials for RPC authentication.
    public static func lightningEclair(rpcAuth: RPCAuth) -> Self {
        mainnet()
            .server()
            .rpcBind(.localhost)
            .rpcAllowIP(.localhost)
            .rpcAuth(rpcAuth)
            .txIndex()
            .blockFilterIndex(.all)
            .rpcPort(Mainnet.defaultRPCPort)
    }

    /// A full node configured for solo mining.
    ///
    /// Enables `txindex`, allocates a large DB cache, and sets a minimum
    /// fee filter for block templates.
    ///
    /// - Parameter rpcAuth: Credentials for RPC authentication.
    public static func mining(rpcAuth: RPCAuth) -> Self {
        mainnet()
            .server()
            .rpcBind(.localhost)
            .rpcAllowIP(.localhost)
            .rpcAuth(rpcAuth)
            .txIndex()
            .dbCache(4000)
            .blockMinTxFee(.satoshisPerByte(1))
            .blockMaxWeight(3_996_000)
    }

    /// A node with all networking disabled, suitable for offline signing,
    /// air-gapped validation, or reproducible testing against a fixed chain state.
    ///
    /// - Parameter rpcAuth: Credentials for RPC authentication.
    public static func nonSyncing(rpcAuth: RPCAuth) -> Self {
        mainnet()
            .server()
            .rpcBind(.localhost)
            .rpcAllowIP(.localhost)
            .rpcAuth(rpcAuth)
            .prune(.minimum)
            .networkActive(false)
            .listen(false)
    }
}
