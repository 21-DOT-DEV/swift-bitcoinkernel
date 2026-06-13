//
//  BitcoinConfig+Client.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

// MARK: - Endpoint & Cookie Derivation

extension BitcoinConfig {

    /// The RPC port the daemon listens on: the explicit ``rpcPort(_:)``
    /// override, or the network's default.
    public var resolvedRPCPort: UInt16 {
        rpcPortOverride ?? N.defaultRPCPort
    }

    /// The local JSON-RPC endpoint, `http://127.0.0.1:<resolvedRPCPort>`.
    public var rpcEndpoint: URL {
        URL(string: "http://127.0.0.1:\(resolvedRPCPort)")!
    }

    /// The RPC cookie file Bitcoin Core writes at startup, derived from the data
    /// directory and the network subdirectory (`<datadir>/<network>/.cookie`).
    ///
    /// `nil` when no data directory was set via ``dataDir(_:)``, in which case
    /// the cookie path cannot be derived and cookie-based connection helpers
    /// such as ``Daemon/startAndConnect(with:timeout:)`` throw.
    public var cookieURL: URL? {
        guard let dataDirectory else { return nil }
        var url = URL(fileURLWithPath: dataDirectory)
        if !N.dataDirName.isEmpty {
            url.appendPathComponent(N.dataDirName)
        }
        return url.appendingPathComponent(".cookie")
    }
}
