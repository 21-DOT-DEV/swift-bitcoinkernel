//
//  LogLevel.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// The minimum severity at which a ``LogCategory`` emits messages. Set
/// per-category via ``setLogLevel(category:level:)``.
///
/// `Comparable` conformance lets you compare levels directly:
/// `level >= .info`. The ordering is `trace < debug < info`, so setting
/// a category's level to `.info` suppresses its `trace` and `debug` lines.
///
/// Maps to `btck_LogLevel` constants in the kernel C API.
public enum LogLevel: UInt8, Sendable, CaseIterable, Codable, Comparable {
    /// Finest-grained logging — per-step internals useful for kernel
    /// development but overwhelming in normal operation.
    case trace = 0

    /// Detailed debugging information — suitable for active
    /// troubleshooting of validation failures or sync issues.
    case debug = 1

    /// General informational messages — the default level for each
    /// category; appropriate for always-on production logging.
    case info  = 2

    /// Raw-value-based ordering: `trace < debug < info`.
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
