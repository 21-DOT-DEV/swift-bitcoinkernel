//
//  KernelAppSettings+Endpoints.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import BitcoinKernel
import Foundation

// MARK: - Endpoint presets

/// A known Esplora-compatible HTTP block source — a curated label the
/// first-launch picker offers. KernelApp does not pick one automatically;
/// the user must make an explicit choice.
///
/// Every preset here is backed by a publicly-documented API-compatible
/// instance of [Blockstream Esplora](https://github.com/Blockstream/esplora)
/// or [mempool.space](https://github.com/mempool/mempool) (a superset of
/// Esplora). Self-hosted endpoints are entered free-form in the settings
/// "Custom URL" field — they don't need to appear in this enum.
enum BlockSourcePreset: String, CaseIterable, Identifiable, Sendable {
    // mempool.space
    case mempoolSpaceMainnet
    case mempoolSpaceTestnet
    case mempoolSpaceTestnet4
    case mempoolSpaceSignet
    // Blockstream.info
    case blockstreamInfoMainnet
    case blockstreamInfoTestnet

    var id: String { rawValue }

    /// Human-readable name for the picker row.
    var displayName: String {
        switch self {
        case .mempoolSpaceMainnet:   return "mempool.space"
        case .mempoolSpaceTestnet:   return "mempool.space (testnet)"
        case .mempoolSpaceTestnet4:  return "mempool.space (testnet4)"
        case .mempoolSpaceSignet:    return "mempool.space (signet)"
        case .blockstreamInfoMainnet: return "blockstream.info"
        case .blockstreamInfoTestnet: return "blockstream.info (testnet)"
        }
    }

    /// Longer description shown under the preset name — explains the
    /// operator and any rate-limit or privacy posture the user should know.
    var subtitle: String {
        switch self {
        case .mempoolSpaceMainnet, .mempoolSpaceTestnet,
             .mempoolSpaceTestnet4, .mempoolSpaceSignet:
            return "Community-run, rate-limited, self-hostable."
        case .blockstreamInfoMainnet, .blockstreamInfoTestnet:
            return "Run by Blockstream. Rate-limited."
        }
    }

    /// Base URL for the API root — the same URL passed to
    /// ``EsploraBlockSource/init(endpoint:urlSession:minimumInterRequestDelay:maximumRetries:baseRetryDelay:)``.
    var url: URL {
        switch self {
        case .mempoolSpaceMainnet:    return URL(string: "https://mempool.space/api")!
        case .mempoolSpaceTestnet:    return URL(string: "https://mempool.space/testnet/api")!
        case .mempoolSpaceTestnet4:   return URL(string: "https://mempool.space/testnet4/api")!
        case .mempoolSpaceSignet:     return URL(string: "https://mempool.space/signet/api")!
        case .blockstreamInfoMainnet: return URL(string: "https://blockstream.info/api")!
        case .blockstreamInfoTestnet: return URL(string: "https://blockstream.info/testnet/api")!
        }
    }

    /// The ``ChainType`` this preset serves.
    var chainType: ChainType {
        switch self {
        case .mempoolSpaceMainnet, .blockstreamInfoMainnet: return .mainnet
        case .mempoolSpaceTestnet, .blockstreamInfoTestnet: return .testnet
        case .mempoolSpaceTestnet4:                         return .testnet4
        case .mempoolSpaceSignet:                           return .signet
        }
    }
}

extension BlockSourcePreset {
    /// Presets that serve the given chain. Used by the first-launch picker
    /// to narrow the list to sensible options for the user's current chain
    /// selection.
    ///
    /// - Parameter chainType: Chain to filter by.
    /// - Returns: Presets in declaration order whose ``chainType`` matches.
    ///   Empty for ``ChainType/regtest`` (no public regtest explorer exists;
    ///   regtest runs against in-app mock sources only).
    static func presets(for chainType: ChainType) -> [BlockSourcePreset] {
        allCases.filter { $0.chainType == chainType }
    }
}
