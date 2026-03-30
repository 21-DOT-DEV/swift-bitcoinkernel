//
//  BitcoinConfig+Debug.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

// MARK: - Debug and Logging Options

extension BitcoinConfig {

    /// Enable logging for the specified category.
    ///
    /// Call multiple times to log multiple categories.
    /// Use `.all` to enable all categories.
    public func debug(_ category: DebugCategory) -> Self {
        appending("debug", category.rawValue)
    }

    /// Exclude a category from debug logging.
    ///
    /// Call multiple times to exclude multiple categories.
    public func debugExclude(_ category: DebugCategory) -> Self {
        appending("debugexclude", category.rawValue)
    }

    /// Include IP addresses in debug output.
    public func logIPs(_ enabled: Bool = true) -> Self {
        appending("logips", bool: enabled)
    }

    /// Prepend log messages with a timestamp.
    public func logTimestamps(_ enabled: Bool = true) -> Self {
        appending("logtimestamps", bool: enabled)
    }

    /// Prepend log messages with the name of the thread that generated them.
    public func logThreadNames(_ enabled: Bool = true) -> Self {
        appending("logthreadnames", bool: enabled)
    }

    /// Prepend log messages with the source location (file + line number).
    public func logSourceLocations(_ enabled: Bool = true) -> Self {
        appending("logsourcelocations", bool: enabled)
    }

    /// Set the verbosity level for all log categories.
    ///
    /// To set per-category levels, use `"-loglevel=<category>:<level>"` via `.raw()`.
    public func logLevel(_ level: LogLevel) -> Self {
        appending("loglevel", level.rawValue)
    }

    /// Send log output to `stdout` instead of `debug.log`.
    public func printToConsole(_ enabled: Bool = true) -> Self {
        appending("printtoconsole", bool: enabled)
    }

    /// Shrink `debug.log` on startup if it grows too large.
    public func shrinkDebugFile(_ enabled: Bool = true) -> Self {
        appending("shrinkdebugfile", bool: enabled)
    }

    /// How many recent blocks to check on startup (0 = all, default 6).
    public func checkBlocks(_ count: UInt) -> Self {
        appending("checkblocks", count)
    }

    /// Thoroughness of block and chain validation (0–4, default 3).
    public func checkLevel(_ level: UInt) -> Self {
        appending("checklevel", min(4, level))
    }

    /// Set the internal clock to a fixed UNIX timestamp for deterministic
    /// testing. Use 0 to restore real-time.
    public func mockTime(_ timestamp: UInt) -> Self {
        appending("mocktime", timestamp)
    }

    /// Stop syncing and exit after reaching this block height.
    /// Useful for benchmarking or reproducible test environments.
    public func stopAtHeight(_ height: UInt) -> Self {
        appending("stopatheight", height)
    }

    /// Override the block version for newly mined blocks.
    ///
    /// Used to test soft-fork activation scenarios.
    public func blockVersion(_ version: Int) -> Self {
        appending("blockversion", version)
    }

    /// Whitelist peers connecting on the given address:port.
    ///
    /// Whitelisted peers are never disconnected and relay non-standard
    /// transactions if `-whitelistrelay=1` is set.
    public func whiteBind(_ address: String) -> Self {
        appending("whitebind", address)
    }

    /// Maximum size of the signature cache in MiB (default 32).
    public func maxSigCacheSize(_ mb: UInt) -> Self {
        appending("maxsigcachesize", mb)
    }
}
