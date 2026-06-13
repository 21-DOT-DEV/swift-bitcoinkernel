//
//  DebugLog.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Locates and reads the embedded daemon's `debug.log`, which Bitcoin Core
/// writes under the (network-subdirectoried) data directory.
enum DebugLog {

    /// The `debug.log` path for the currently-selected network. Bitcoin Core
    /// puts mainnet at the data-directory root and other networks under a
    /// subdirectory (`regtest`, `signet`, `testnet3`).
    static var url: URL {
        let network = BitcoinNetwork(
            rawValue: UserDefaults.standard.string(forKey: "bitcoin_network") ?? ""
        ) ?? .mainnet
        let subdirectory: String = switch network {
        case .mainnet: ""
        case .testnet: "testnet3"
        case .signet:  "signet"
        case .regtest: "regtest"
        }
        var directory = DaemonConfig.dataDirectory
        if !subdirectory.isEmpty { directory.appendPathComponent(subdirectory) }
        return directory.appendingPathComponent("debug.log")
    }

    /// The tail of the log (last `maxBytes`), or an empty string when no log
    /// exists yet. Reads only the tail so a multi-gigabyte mainnet log never
    /// loads whole.
    static func tail(maxBytes: Int = 256 * 1024) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
