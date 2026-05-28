//
//  EsploraAPI.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Internal helpers for constructing Esplora-compatible HTTP endpoints and
/// translating between Bitcoin's hash conventions and Esplora's display-hex.
///
/// Esplora serves hashes as 64-char **display-order** hex — the same
/// orientation block explorers show humans. The kernel stores hashes in
/// **internal byte order** (reversed from display). This file owns that
/// translation so callers in ``EsploraBlockSource`` don't need to think
/// about it.
enum EsploraAPI {
    static func tipHeightURL(base: URL) -> URL {
        base.appending(path: "blocks/tip/height", directoryHint: .notDirectory)
    }

    static func tipHashURL(base: URL) -> URL {
        base.appending(path: "blocks/tip/hash", directoryHint: .notDirectory)
    }

    static func blockHashAtHeightURL(base: URL, height: Int) -> URL {
        base.appending(path: "block-height/\(height)", directoryHint: .notDirectory)
    }

    static func blockHeaderURL(base: URL, hashInternal: Data) -> URL {
        base.appending(
            path: "block/\(displayHex(fromInternal: hashInternal))/header",
            directoryHint: .notDirectory
        )
    }

    static func blockRawURL(base: URL, hashInternal: Data) -> URL {
        base.appending(
            path: "block/\(displayHex(fromInternal: hashInternal))/raw",
            directoryHint: .notDirectory
        )
    }

    // MARK: - Byte-order & hex helpers

    /// Convert a 32-byte internal-order hash to its Esplora display-hex form.
    static func displayHex(fromInternal hash: Data) -> String {
        Data(hash.reversed()).map { String(format: "%02x", $0) }.joined()
    }

    /// Parse an Esplora display-hex hash into 32 internal-order bytes.
    ///
    /// - Returns: The parsed internal-order bytes, or `nil` if the input is
    ///   not exactly 64 hex characters.
    static func internalHash(fromDisplayHex hex: String) -> Data? {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 64, let display = data(fromHex: trimmed) else { return nil }
        return Data(display.reversed())
    }

    /// Parse an ASCII-hex string of any even length into raw bytes. Lenient:
    /// returns `nil` on any non-hex character.
    static func data(fromHex hex: String) -> Data? {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}

// MARK: - Public URL accessors for known Esplora-compatible endpoints

/// Known public [Esplora](https://github.com/Blockstream/esplora)-compatible
/// HTTP endpoints for use with ``EsploraBlockSource``.
///
/// Callers pick one explicitly — ``BitcoinKernel`` does **not** bake in a
/// default, because the block source is the network trust authority for
/// chainstate validation input. Silently choosing one on behalf of the user
/// would mask a consequential decision.
///
/// These six accessors cover the public Bitcoin Core networks that
/// mempool.space and blockstream.info serve today. To hit a self-hosted
/// Esplora instance, construct the `URL` directly and pass it to
/// ``EsploraBlockSource/init(endpoint:urlSession:minimumInterRequestDelay:maximumRetries:baseRetryDelay:)``.
public extension URL {
    /// `https://mempool.space/api` — mempool.space mainnet.
    ///
    /// Mainnet IBD from any public Esplora is impractical on mobile (~600 GB).
    /// Ship this only on desktop, or use it to check tip state without
    /// actually syncing.
    static let mempoolSpaceMainnet = URL(string: "https://mempool.space/api")!

    /// `https://mempool.space/testnet/api` — mempool.space testnet3.
    ///
    /// Testnet3 is the legacy Bitcoin test network. For new deployments,
    /// prefer ``mempoolSpaceTestnet4`` — testnet3 accumulated difficulty
    /// anomalies over its long lifetime that testnet4 was reset to avoid.
    static let mempoolSpaceTestnet = URL(string: "https://mempool.space/testnet/api")!

    /// `https://mempool.space/testnet4/api` — mempool.space testnet4.
    ///
    /// Testnet4 reset the difficulty-reset-exploit accumulation of testnet3
    /// and is the recommended network for contemporary test deployments.
    static let mempoolSpaceTestnet4 = URL(string: "https://mempool.space/testnet4/api")!

    /// `https://mempool.space/signet/api` — mempool.space
    /// [signet](https://github.com/bitcoin/bips/blob/master/bip-0325.mediawiki).
    ///
    /// The recommended real-network sync target for swift-bitcoinkernel today.
    /// Signet is small (~50 MB at typical tip height) and produces
    /// predictable, uncontentious blocks.
    static let mempoolSpaceSignet = URL(string: "https://mempool.space/signet/api")!

    /// `https://blockstream.info/api` — blockstream.info mainnet.
    ///
    /// Alternative mainnet Esplora instance for diversification or when
    /// mempool.space is unavailable. Same rate-limit caveats as
    /// ``mempoolSpaceMainnet``.
    static let blockstreamInfo = URL(string: "https://blockstream.info/api")!

    /// `https://blockstream.info/testnet/api` — blockstream.info testnet3.
    static let blockstreamInfoTestnet = URL(string: "https://blockstream.info/testnet/api")!
}
