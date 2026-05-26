//
//  BitcoinConfig+Core.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

// MARK: - Core Node Options

extension BitcoinConfig {

    /// Accept command line and JSON-RPC commands.
    public func server(_ enabled: Bool = true) -> Self {
        var copy = appending("server", bool: enabled)
        if enabled { copy = copy.setting(.server) }
        return copy
    }

    /// Run in the background as a daemon.
    public func daemon(_ enabled: Bool = true) -> Self {
        appending("daemon", bool: enabled)
    }

    /// Wait for initialization to be finished before exiting (with `-daemon`).
    public func daemonWait(_ enabled: Bool = true) -> Self {
        appending("daemonwait", bool: enabled)
    }

    /// Specify data directory.
    public func dataDir(_ path: String) -> Self {
        appending("datadir", path)
    }

    /// Specify blocks directory.
    public func blocksDir(_ path: String) -> Self {
        appending("blocksdir", path)
    }

    /// Set database cache size in MiB (minimum 4 MiB).
    ///
    /// When not specified, Bitcoin Core defaults to 1024 MiB on systems with
    /// at least 4096 MiB of RAM, and 450 MiB otherwise.
    public func dbCache(_ mb: UInt) -> Self {
        appending("dbcache", max(4, mb))
    }

    /// Enable pruning to reduce storage requirements.
    ///
    /// - Note: `PruneMode.size` sets `.pruneSize` in `ConfigFlags`, enabling
    ///   `validate()` to detect `txindex`/`coinstatsindex` conflicts.
    public func prune(_ mode: PruneMode) -> Self {
        var copy = appending("prune", mode.rawValue)
        if case .size = mode { copy = copy.setting(.pruneSize) }
        return copy
    }

    /// Maintain a full transaction index (`txindex=1`).
    public func txIndex(_ enabled: Bool = true) -> Self {
        var copy = appending("txindex", bool: enabled)
        if enabled { copy = copy.setting(.txIndex) }
        return copy
    }

    /// Maintain coinstats index used by the `gettxoutsetinfo` RPC.
    public func coinStatsIndex(_ enabled: Bool = true) -> Self {
        var copy = appending("coinstatsindex", bool: enabled)
        if enabled { copy = copy.setting(.coinStatsIndex) }
        return copy
    }

    /// Maintain a transaction output spender index (v31+).
    ///
    /// When enabled, `gettxspendingprevout` can return the block hash of
    /// confirmed spending transactions.
    public func txoSpenderIndex(_ enabled: Bool = true) -> Self {
        appending("txospenderindex", bool: enabled)
    }

    /// Maintain compact block filters for peer and personal use.
    public func blockFilterIndex(_ mode: BlockFilterMode) -> Self {
        var copy = appending("blockfilterindex", mode)
        if case .all = mode { copy = copy.setting(.blockFilterIndexAll) }
        return copy
    }

    /// Do not accept transactions from remote peers (blocks-only mode).
    public func blocksOnly(_ enabled: Bool = true) -> Self {
        var copy = appending("blocksonly", bool: enabled)
        if enabled { copy = copy.setting(.blocksOnly) }
        return copy
    }

    /// Keep the transaction memory pool below this many MiB (minimum 5 MiB).
    public func maxMempool(_ mb: UInt) -> Self {
        var copy = appending("maxmempool", max(5, mb))
        copy = copy.setting(.maxMempool)
        return copy
    }

    /// Evict transactions from the mempool after this many hours (minimum 1).
    public func mempoolExpiry(_ hours: UInt) -> Self {
        appending("mempoolexpiry", max(1, hours))
    }

    /// Save the mempool to disk on shutdown and load it on startup.
    public func persistMempool(_ enabled: Bool = true) -> Self {
        appending("persistmempool", bool: enabled)
    }

    /// Set the number of script verification threads (`-par`).
    /// Use 0 for auto, negative to leave that many cores free.
    public func par(_ threads: Int) -> Self {
        appending("par", threads)
    }

    /// Specify PID file path (only used when `-daemon` is set).
    public func pid(_ filename: String) -> Self {
        appending("pid", filename)
    }

    /// Rebuild chain state and block index on startup.
    public func reindex() -> Self {
        appending("-reindex")
    }

    /// Rebuild chain state only (faster than full reindex).
    public func reindexChainstate() -> Self {
        appending("-reindex-chainstate")
    }

    /// If set, skip validation of scripts in blocks before this block hash.
    public func assumeValid(_ hash: String) -> Self {
        appending("assumevalid", hash)
    }

    /// Execute a command when a relevant alert is received.
    public func alertNotify(_ cmd: String) -> Self {
        appending("alertnotify", cmd)
    }

    /// Execute a command when the best block changes.
    public func blockNotify(_ cmd: String) -> Self {
        appending("blocknotify", cmd)
    }

    /// Execute a command after startup is complete.
    public func startupNotify(_ cmd: String) -> Self {
        appending("startupnotify", cmd)
    }

    /// Execute a command before beginning shutdown.
    public func shutdownNotify(_ cmd: String) -> Self {
        appending("shutdownnotify", cmd)
    }

    /// Import blocks from an external blk\*.dat file on startup.
    ///
    /// Call multiple times to import from multiple files in order.
    public func loadBlock(_ path: String) -> Self {
        appending("loadblock", path)
    }

    /// Path to the `bitcoin.conf` configuration file.
    ///
    /// Useful for app bundles or sandboxed macOS apps that place the config
    /// inside a known container path rather than the default `<datadir>/bitcoin.conf`.
    public func conf(_ path: String) -> Self {
        appending("conf", path)
    }

    /// Specify an additional configuration file to include.
    public func includeConf(_ path: String) -> Self {
        appending("includeconf", path)
    }
}
