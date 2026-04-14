//
//  BitcoinConfig.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

// MARK: - ConfigFlags

/// Tracks which conflict-relevant options have been set on a `BitcoinConfig`.
///
/// Using an `OptionSet` instead of string parsing keeps `validate()` O(1)
/// and unambiguous. Flags are only set by typed methods; `.raw()` cannot
/// set them — that is the explicit contract of an escape hatch.
///
/// `UInt32` is used to accommodate all four implementation phases without
/// a breaking change.
struct ConfigFlags: OptionSet, Sendable {
    let rawValue: UInt32

    static let txIndex        = ConfigFlags(rawValue: 1 << 0)
    static let pruneSize      = ConfigFlags(rawValue: 1 << 1)
    static let coinStatsIndex = ConfigFlags(rawValue: 1 << 2)
    static let server         = ConfigFlags(rawValue: 1 << 3)
    static let rpcBind        = ConfigFlags(rawValue: 1 << 4)
    static let rpcAllowIP     = ConfigFlags(rawValue: 1 << 5)
    static let rpcAuth        = ConfigFlags(rawValue: 1 << 6)
    static let blocksOnly          = ConfigFlags(rawValue: 1 << 7)
    static let maxMempool          = ConfigFlags(rawValue: 1 << 8)
    // Phase 2
    static let disableWallet       = ConfigFlags(rawValue: 1 << 9)
    static let walletOption        = ConfigFlags(rawValue: 1 << 10)
    static let connect             = ConfigFlags(rawValue: 1 << 11)
    static let peerBlockFilters    = ConfigFlags(rawValue: 1 << 12)
    static let blockFilterIndexAll = ConfigFlags(rawValue: 1 << 13)
    static let listen              = ConfigFlags(rawValue: 1 << 14)
    static let maxUploadTarget     = ConfigFlags(rawValue: 1 << 15)
    static let rpcCookieFile       = ConfigFlags(rawValue: 1 << 16)
}

// MARK: - BitcoinConfig

/// A type-safe, fluent builder for Bitcoin Core CLI arguments.
///
/// `BitcoinConfig` accumulates validated `-key=value` arguments and tracks
/// conflict-relevant state in a `ConfigFlags` bitmask. Call `validate()` before
/// passing the config to `Daemon.start(with:)` to surface warnings and errors.
///
/// Create configs exclusively via the static factory methods:
/// ```swift
/// BitcoinConfig.mainnet()
/// BitcoinConfig.regtest()
/// ```
///
/// The initializer is intentionally `internal` — phantom typing requires
/// that the network type is always inferred from the factory call site.
public struct BitcoinConfig<N: BitcoinNetwork>: Sendable {
    private var args: [String]
    var flags: ConfigFlags

    /// Internal — use static factories instead.
    init() {
        if let flag = N.flag {
            args = [flag]
        } else {
            args = []
        }
        flags = []
    }

    /// The accumulated CLI argument list, ready to pass to `Daemon.start(_:)`.
    public var arguments: [String] { args }

    // MARK: Internal fluent helpers
    //
    // These are `internal` (not `private`) because they are called from
    // extensions defined in separate files within the same module.
    // ConfigFlags is also `internal` for the same reason.

    func appending(_ arg: String) -> Self {
        var copy = self
        copy.args.append(arg)
        return copy
    }

    func appending(_ key: String, _ value: some CustomStringConvertible) -> Self {
        appending("-\(key)=\(value)")
    }

    func appending(_ key: String, bool: Bool) -> Self {
        appending("-\(key)=\(bool ? 1 : 0)")
    }

    func setting(_ flag: ConfigFlags) -> Self {
        var copy = self
        copy.flags.insert(flag)
        return copy
    }
}

// MARK: - Static Entry Points

extension BitcoinConfig where N == Mainnet {
    /// Creates a configuration for Bitcoin mainnet.
    public static func mainnet() -> BitcoinConfig<Mainnet> {
        BitcoinConfig<Mainnet>()
    }
}

extension BitcoinConfig where N == Testnet {
    /// Creates a configuration for Bitcoin testnet3.
    ///
    /// - Warning: testnet3 is deprecated in Bitcoin Core. Use `testnet4()` instead.
    @available(*, deprecated, message: "testnet3 is deprecated in Bitcoin Core. Use .testnet4() instead.")
    public static func testnet() -> BitcoinConfig<Testnet> {
        BitcoinConfig<Testnet>()
    }
}

extension BitcoinConfig where N == Testnet4 {
    /// Creates a configuration for Bitcoin testnet4.
    public static func testnet4() -> BitcoinConfig<Testnet4> {
        BitcoinConfig<Testnet4>()
    }
}

extension BitcoinConfig where N == Regtest {
    /// Creates a configuration for Bitcoin regtest.
    public static func regtest() -> BitcoinConfig<Regtest> {
        BitcoinConfig<Regtest>()
    }
}

extension BitcoinConfig where N == Signet {
    /// Creates a configuration for Bitcoin signet.
    public static func signet() -> BitcoinConfig<Signet> {
        BitcoinConfig<Signet>()
    }
}
