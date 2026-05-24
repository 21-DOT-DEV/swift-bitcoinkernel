//
//  NetworkTypes.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Compile-time marker for a Bitcoin network.
///
/// Conforming types are uninhabited enums used solely as phantom type
/// parameters on `BitcoinConfig<N>`. They carry no runtime cost.
public protocol BitcoinNetwork: Sendable {
    /// The CLI flag appended to the argument list (e.g. `-regtest`), or `nil`
    /// for mainnet (which has no flag).
    static var flag: String? { get }

    /// The default P2P port for this network.
    static var defaultP2PPort: UInt16 { get }

    /// The default RPC port for this network.
    static var defaultRPCPort: UInt16 { get }
}

/// Bitcoin mainnet (production).
public enum Mainnet: BitcoinNetwork {
    public static let flag: String? = nil
    public static let defaultP2PPort: UInt16 = 8333
    public static let defaultRPCPort: UInt16 = 8332
}

/// Bitcoin testnet3.
///
/// - Warning: testnet3 is deprecated in Bitcoin Core. Prefer ``Testnet4``.
public enum Testnet: BitcoinNetwork {
    public static let flag: String? = "-testnet"
    public static let defaultP2PPort: UInt16 = 18333
    public static let defaultRPCPort: UInt16 = 18332
}

/// Bitcoin testnet4.
public enum Testnet4: BitcoinNetwork {
    public static let flag: String? = "-testnet4"
    public static let defaultP2PPort: UInt16 = 48333
    public static let defaultRPCPort: UInt16 = 48332
}

/// Bitcoin regtest (regression test network).
public enum Regtest: BitcoinNetwork {
    public static let flag: String? = "-regtest"
    public static let defaultP2PPort: UInt16 = 18444
    public static let defaultRPCPort: UInt16 = 18443
}

/// Bitcoin signet.
public enum Signet: BitcoinNetwork {
    public static let flag: String? = "-signet"
    public static let defaultP2PPort: UInt16 = 38333
    public static let defaultRPCPort: UInt16 = 38332
}
