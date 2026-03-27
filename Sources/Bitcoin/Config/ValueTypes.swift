//
//  ValueTypes.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

// MARK: - IPAddress

/// A validated IP address (v4, v6, or CIDR range) for use in Bitcoin Core config.
///
/// Supports CIDR notation (e.g. `"192.168.1.0/24"`) for `rpcallowip`.
public struct IPAddress: ExpressibleByStringLiteral, CustomStringConvertible, Sendable, Hashable {
    private let raw: String

    /// Creates an `IPAddress` from a raw string without validation.
    /// Used by `ExpressibleByStringLiteral` and static constants.
    private init(raw: String) {
        self.raw = raw
    }

    /// Creates an `IPAddress` from a string literal.
    public init(stringLiteral value: String) {
        self.raw = value
    }

    public var description: String { raw }

    /// `127.0.0.1` — the local loopback address.
    public static let localhost: IPAddress = "127.0.0.1"

    /// `0.0.0.0` — bind to all interfaces.
    public static let allInterfaces: IPAddress = "0.0.0.0"

    /// `::1` — IPv6 loopback.
    public static let loopbackIPv6: IPAddress = "::1"
}

// MARK: - RPCAuth

/// A Bitcoin Core `rpcauth` credential in the form `user:salt$hmac`.
///
/// The `rawValue` produced by this type is suitable for passing directly
/// to the `-rpcauth=` CLI flag.
public struct RPCAuth: Sendable {
    /// The RPC username.
    public let username: String

    /// The random salt used when hashing the password.
    public let salt: String

    /// The HMAC-SHA256 of the password with the salt.
    public let passwordHMAC: String

    /// Creates an `RPCAuth` from its component parts.
    public init(username: String, salt: String, passwordHMAC: String) {
        self.username = username
        self.salt = salt
        self.passwordHMAC = passwordHMAC
    }

    /// Parses an `RPCAuth` from a raw `user:salt$hmac` string.
    ///
    /// Returns `nil` if the string does not match the expected format.
    public init?(rawString: String) {
        let dollarParts = rawString.split(separator: "$", maxSplits: 1)
        guard dollarParts.count == 2 else { return nil }
        let colonParts = dollarParts[0].split(separator: ":", maxSplits: 1)
        guard colonParts.count == 2 else { return nil }
        self.username = String(colonParts[0])
        self.salt = String(colonParts[1])
        self.passwordHMAC = String(dollarParts[1])
    }

    /// The raw `user:salt$hmac` string suitable for `-rpcauth=`.
    public var rawValue: String {
        "\(username):\(salt)$\(passwordHMAC)"
    }
}

// MARK: - PruneMode

/// Controls Bitcoin Core's block storage pruning behaviour.
public enum PruneMode: Sendable {
    /// Pruning disabled. Full block history is retained.
    case disabled

    /// Manual pruning. Use the `pruneblockchain` RPC to prune explicitly.
    case manual

    /// Automatic pruning to a target disk size (minimum 550 MiB).
    ///
    /// - Precondition: `mb >= 550`
    case size(mb: UInt)

    /// The minimum allowed prune target: 550 MiB.
    public static let minimum: PruneMode = .size(mb: 550)

    /// The integer value passed to the `-prune=` flag.
    public var rawValue: Int {
        switch self {
        case .disabled: return 0
        case .manual:   return 1
        case .size(let mb):
            precondition(mb >= 550, "PruneMode.size requires mb >= 550")
            return Int(mb)
        }
    }
}

// MARK: - BlockFilterMode

/// Controls whether Bitcoin Core builds compact block filters.
public enum BlockFilterMode: Sendable {
    /// Block filters disabled.
    case disabled

    /// All filter types enabled (passes `1` to `-blockfilterindex`).
    case all

    /// Only the `basic` filter type enabled.
    case basic
}

extension BlockFilterMode: CustomStringConvertible {
    public var description: String {
        switch self {
        case .disabled: return "0"
        case .all:      return "1"
        case .basic:    return "basic"
        }
    }
}

// MARK: - FeeRate

/// A fee rate expressed in BTC per kilovbyte (BTC/kvB).
///
/// Use the factory methods to construct values from common units:
/// ```swift
/// .satoshisPerByte(1)    // 1 sat/vbyte = 0.00001 BTC/kvB
/// .btcPerKvB(0.00001)
/// ```
public struct FeeRate: Sendable, CustomStringConvertible {
    private let btcPerKvB: Decimal

    private init(btcPerKvB: Decimal) {
        precondition(btcPerKvB >= 0, "FeeRate must be non-negative")
        self.btcPerKvB = btcPerKvB
    }

    /// Creates a `FeeRate` from satoshis per vbyte.
    ///
    /// 1 sat/vbyte = 0.00001 BTC/kvB.
    public static func satoshisPerByte(_ satoshis: Decimal) -> FeeRate {
        FeeRate(btcPerKvB: satoshis / 100_000)
    }

    /// Creates a `FeeRate` directly from BTC per kilovbyte.
    public static func btcPerKvB(_ value: Decimal) -> FeeRate {
        FeeRate(btcPerKvB: value)
    }

    /// The decimal string representation passed to Bitcoin Core CLI flags (BTC/kvB).
    public var description: String {
        NSDecimalNumber(decimal: btcPerKvB).stringValue
    }
}

// MARK: - NetworkType

/// The network transport layer used to filter peer connections.
///
/// Passed to `-onlynet=` to restrict Bitcoin Core to a single network type.
public enum NetworkType: String, Sendable {
    case ipv4
    case ipv6
    case onion
    case i2p
    case cjdns
}

// MARK: - AddressType

/// The output script type used for receiving and change addresses.
///
/// Passed to `-addresstype=` and `-changetype=`.
public enum AddressType: String, Sendable {
    case legacy
    case p2shSegwit = "p2sh-segwit"
    case bech32
    case bech32m
}

// MARK: - ZMQEndpoint

/// A ZeroMQ publish endpoint address passed to Bitcoin Core ZMQ options.
///
/// ```swift
/// .zmqPubRawBlock(.tcp(port: 28332))
/// .zmqPubRawTx(.tcp(host: "127.0.0.1", port: 28333))
/// ```
public struct ZMQEndpoint: Sendable, CustomStringConvertible {
    private let raw: String

    private init(_ raw: String) {
        self.raw = raw
    }

    /// A TCP endpoint bound to `127.0.0.1` on the given port.
    public static func tcp(port: UInt16) -> ZMQEndpoint {
        ZMQEndpoint("tcp://127.0.0.1:\(port)")
    }

    /// A TCP endpoint bound to an explicit host and port.
    public static func tcp(host: String, port: UInt16) -> ZMQEndpoint {
        ZMQEndpoint("tcp://\(host):\(port)")
    }

    /// The raw endpoint string passed to the `-zmq*=` flag (e.g. `"tcp://127.0.0.1:28332"`).
    public var description: String { raw }
}

// MARK: - DebugCategory

/// A logging category for the Bitcoin Core `-debug=` flag.
///
/// Pass `.all` to enable every category. Call `.debug()` multiple times to
/// enable a selective subset.
public enum DebugCategory: String, Sendable {
    case all
    case addrman
    case bench
    case blockstorage
    case cmpctblock
    case coindb
    case estimatefee
    case http
    case i2p
    case ipc
    case leveldb
    case libevent
    case mempool
    case mempoolrej
    case net
    case proxy
    case prune
    case rand
    case reindex
    case rpc
    case scan
    case selectcoins
    case tor
    case txpackages
    case txreconciliation
    case validation
    case walletdb
    case zmq
}

// MARK: - LogLevel

/// The verbosity level for Bitcoin Core's structured logging (`-loglevel=`).
public enum LogLevel: String, Sendable {
    case info
    case debug
    case trace
}
