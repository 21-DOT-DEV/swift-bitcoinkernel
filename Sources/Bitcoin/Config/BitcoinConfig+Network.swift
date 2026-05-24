//
//  BitcoinConfig+Network.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

// MARK: - P2P Network Options

extension BitcoinConfig {

    /// Add a peer node to connect to and attempt to keep connected.
    ///
    /// Call multiple times to add multiple peers.
    public func addNode(_ host: String) -> Self {
        appending("addnode", host)
    }

    /// Number of seconds misbehaving peers are banned (default 86400).
    public func banTime(_ seconds: UInt) -> Self {
        appending("bantime", seconds)
    }

    /// Bind to a specific address and port for incoming connections.
    ///
    /// Call multiple times to bind to multiple addresses.
    /// Optional suffix `=onion` restricts the bind to Tor connections.
    public func bind(_ address: String) -> Self {
        appending("bind", address)
    }

    /// Connect only to the specified node(s); disables peer discovery.
    ///
    /// When set, `-addnode`, `-seednode`, and `-dnsseed` have no effect.
    ///
    /// Call multiple times to connect to multiple fixed peers.
    public func connect(_ host: String) -> Self {
        var copy = appending("connect", host)
        copy = copy.setting(.connect)
        return copy
    }

    /// Discover own IP address (default 1 unless `-externalip` or `-proxy` is set).
    public func discover(_ enabled: Bool = true) -> Self {
        appending("discover", bool: enabled)
    }

    /// Allow DNS lookups for `-addnode`, `-seednode`, and `-connect`.
    public func dns(_ enabled: Bool = true) -> Self {
        appending("dns", bool: enabled)
    }

    /// Query for peer addresses via DNS lookup on startup.
    public func dnsSeed(_ enabled: Bool = true) -> Self {
        appending("dnsseed", bool: enabled)
    }

    /// Specify your own public IP address.
    public func externalIP(_ ip: IPAddress) -> Self {
        appending("externalip", ip)
    }

    /// Accept incoming connections from peers.
    public func listen(_ enabled: Bool = true) -> Self {
        var copy = appending("listen", bool: enabled)
        if enabled { copy = copy.setting(.listen) }
        return copy
    }

    /// Automatically create and use a Tor hidden service.
    public func listenOnion(_ enabled: Bool = true) -> Self {
        appending("listenonion", bool: enabled)
    }

    /// Maintain at most N connections to peers.
    public func maxConnections(_ count: UInt) -> Self {
        appending("maxconnections", count)
    }

    /// Maximum per-connection receive buffer in kilobytes.
    public func maxReceiveBuffer(_ kb: UInt) -> Self {
        appending("maxreceivebuffer", kb)
    }

    /// Maximum per-connection send buffer in kilobytes.
    public func maxSendBuffer(_ kb: UInt) -> Self {
        appending("maxsendbuffer", kb)
    }

    /// Target daily data upload cap across all peers in MiB (0 = no limit).
    public func maxUploadTarget(_ mb: UInt) -> Self {
        var copy = appending("maxuploadtarget", mb)
        if mb > 0 { copy = copy.setting(.maxUploadTarget) }
        return copy
    }

    /// Disable all P2P network activity.
    public func networkActive(_ enabled: Bool = true) -> Self {
        appending("networkactive", bool: enabled)
    }

    /// Use a SOCKS5 proxy for connections to the Tor network.
    ///
    /// Format: `"host:port"` (e.g. `"127.0.0.1:9050"`).
    public func onion(_ proxy: String) -> Self {
        appending("onion", proxy)
    }

    /// Only connect to nodes via the specified network type.
    ///
    /// Call multiple times to allow multiple network types.
    public func onlyNet(_ type: NetworkType) -> Self {
        appending("onlynet", type.rawValue)
    }

    /// Serve compact block filters to peers per BIP 157 / BIP 158.
    ///
    /// Requires `blockFilterIndex(.all)` — `validate()` will surface this
    /// as a `ConfigError.peerBlockFiltersWithoutIndex` if not set.
    public func peerBlockFilters(_ enabled: Bool = true) -> Self {
        var copy = appending("peerblockfilters", bool: enabled)
        if enabled { copy = copy.setting(.peerBlockFilters) }
        return copy
    }

    /// Listen for peer connections on the specified port.
    public func port(_ port: UInt16) -> Self {
        appending("port", port)
    }

    /// Connect to peers via a SOCKS5 proxy.
    ///
    /// Format: `"host:port"` (e.g. `"127.0.0.1:9050"`).
    public func proxy(_ address: String) -> Self {
        appending("proxy", address)
    }

    /// Randomize credentials for every proxy connection (for privacy).
    public func proxyRandomize(_ enabled: Bool = true) -> Self {
        appending("proxyrandomize", bool: enabled)
    }

    /// Connect to a seed node to retrieve peer addresses, then disconnect.
    ///
    /// Call multiple times for multiple seed nodes.
    public func seedNode(_ host: String) -> Self {
        appending("seednode", host)
    }

    /// Peer connection timeout in milliseconds (default 5000).
    public func timeout(_ ms: UInt) -> Self {
        appending("timeout", ms)
    }

    /// Tor control port address (default `"127.0.0.1:9051"`).
    public func torControl(_ address: String) -> Self {
        appending("torcontrol", address)
    }

    /// Tor control port password.
    public func torPassword(_ password: String) -> Self {
        appending("torpassword", password)
    }

    /// Broadcast own transactions only via Tor or I2P (v31+).
    ///
    /// Prevents the originator's IP address from being revealed to
    /// transaction recipients and avoids linking unrelated transactions
    /// through the same connection. Requires Tor or I2P to be reachable.
    public func privateBroadcast(_ enabled: Bool = true) -> Self {
        appending("privatebroadcast", bool: enabled)
    }

    /// Support filtering of blocks and transactions with bloom filters (BIP37).
    ///
    /// Enable this when serving lightweight/SPV clients that issue `filterload`,
    /// `filteradd`, or `filterclear` messages. Disabled by default in Bitcoin Core.
    public func peerBloomFilters(_ enabled: Bool = true) -> Self {
        appending("peerbloomfilters", bool: enabled)
    }
}
