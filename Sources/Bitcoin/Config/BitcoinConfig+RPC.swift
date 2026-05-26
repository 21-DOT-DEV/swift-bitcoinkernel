//
//  BitcoinConfig+RPC.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

// MARK: - RPC Server Options

extension BitcoinConfig {

    /// Bind to the given address for the RPC interface.
    ///
    /// Call multiple times to bind to multiple addresses.
    public func rpcBind(_ ip: IPAddress) -> Self {
        var copy = appending("rpcbind", ip)
        copy = copy.setting(.rpcBind)
        return copy
    }

    /// Allow JSON-RPC connections from the specified address.
    ///
    /// Call multiple times to allow multiple IP ranges (e.g. CIDR notation).
    ///
    /// ```swift
    /// .rpcAllowIP(.localhost)
    /// .rpcAllowIP("192.168.1.0/24")  // two -rpcallowip= args
    /// ```
    public func rpcAllowIP(_ ip: IPAddress) -> Self {
        var copy = appending("rpcallowip", ip)
        copy = copy.setting(.rpcAllowIP)
        return copy
    }

    /// Listen for RPC connections on this port.
    public func rpcPort(_ port: UInt16) -> Self {
        appending("rpcport", port)
    }

    /// Credentials for JSON-RPC connections.
    ///
    /// Call multiple times to add multiple users.
    public func rpcAuth(_ auth: RPCAuth) -> Self {
        var copy = appending("rpcauth", auth.rawValue)
        copy = copy.setting(.rpcAuth)
        return copy
    }

    /// Number of RPC server threads (1–64, default 4).
    public func rpcThreads(_ count: UInt) -> Self {
        appending("rpcthreads", max(1, min(64, count)))
    }

    /// Depth of the RPC server's work queue (1–1024, default 16).
    public func rpcWorkQueue(_ depth: UInt) -> Self {
        appending("rpcworkqueue", max(1, min(1024, depth)))
    }

    /// Path to the RPC authentication cookie file.
    ///
    /// Defaults to `<datadir>/.cookie`. Useful for sandboxed macOS apps that
    /// read credentials from a known container path rather than the data directory.
    public func rpcCookieFile(_ path: String) -> Self {
        appending("rpccookiefile", path).setting(.rpcCookieFile)
    }

    /// Unix file permission mode for the RPC cookie file (e.g. `"0600"`).
    ///
    /// Restricts who can read the cookie — important when the data directory
    /// is accessible to multiple system users.
    public func rpcCookiePerms(_ mode: String) -> Self {
        appending("rpccookieperms", mode)
    }

    /// Set the serialization format for certain RPC results.
    public func rpcSerialVersion(_ version: UInt) -> Self {
        appending("rpcserialversion", version)
    }

    /// Set a whitelist to filter incoming RPC calls.
    public func rpcWhitelist(_ whitelist: String) -> Self {
        appending("rpcwhitelist", whitelist)
    }

    /// Sets default behavior for rpc whitelisting.
    public func rpcWhitelistDefault(_ enabled: Bool) -> Self {
        appending("rpcwhitelistdefault", bool: enabled)
    }
}
