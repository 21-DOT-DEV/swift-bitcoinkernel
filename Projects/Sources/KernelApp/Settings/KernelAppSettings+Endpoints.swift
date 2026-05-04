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
///
/// ### Onion variants
///
/// `.onion` presets are Tor-only — their hosts will not resolve over
/// clearnet DNS. Callers should filter them via
/// ``presets(for:torRouting:)`` so they're only offered when the user
/// has Tor routing enabled. The `.onion` host addresses are sourced
/// from [Sparrow Wallet's `BroadcastSource`](https://github.com/sparrowwallet/sparrow/blob/master/src/main/java/com/sparrowwallet/sparrow/net/BroadcastSource.java)
/// (v3 onion services, operator-declared).
///
/// ### Community operators
///
/// - `mempool.space` — primary mempool.space deployment.
/// - `mempool.emzy.de` — long-running community mirror operated by
///   Mempool Open Source Project contributor Emzy.
/// - `mempool.bisq.services` — mirror operated by the Bisq DAO.
/// - `blockstream.info` — Blockstream-operated reference instance.
enum BlockSourcePreset: String, CaseIterable, Identifiable, Sendable {
    // mempool.space (clearnet)
    case mempoolSpaceMainnet
    case mempoolSpaceTestnet
    case mempoolSpaceTestnet4
    case mempoolSpaceSignet
    // mempool.space (onion)
    case mempoolSpaceMainnetOnion
    case mempoolSpaceTestnetOnion
    case mempoolSpaceTestnet4Onion
    case mempoolSpaceSignetOnion
    // Blockstream.info (clearnet)
    case blockstreamInfoMainnet
    case blockstreamInfoTestnet
    // Blockstream.info (onion)
    case blockstreamInfoMainnetOnion
    case blockstreamInfoTestnetOnion
    // Community mempool mirrors (mainnet only — mirrors run a mainnet-focused
    // index; operators have historically not published testnet/signet URLs).
    case mempoolEmzyDeMainnet
    case mempoolEmzyDeMainnetOnion
    case mempoolBisqServicesMainnet
    case mempoolBisqServicesMainnetOnion

    var id: String { rawValue }

    /// Human-readable name for the picker row.
    var displayName: String {
        switch self {
        case .mempoolSpaceMainnet:           return "mempool.space"
        case .mempoolSpaceTestnet:           return "mempool.space (testnet)"
        case .mempoolSpaceTestnet4:          return "mempool.space (testnet4)"
        case .mempoolSpaceSignet:            return "mempool.space (signet)"
        case .mempoolSpaceMainnetOnion:      return "mempool.space (Tor)"
        case .mempoolSpaceTestnetOnion:      return "mempool.space (testnet, Tor)"
        case .mempoolSpaceTestnet4Onion:     return "mempool.space (testnet4, Tor)"
        case .mempoolSpaceSignetOnion:       return "mempool.space (signet, Tor)"
        case .blockstreamInfoMainnet:        return "blockstream.info"
        case .blockstreamInfoTestnet:        return "blockstream.info (testnet)"
        case .blockstreamInfoMainnetOnion:   return "blockstream.info (Tor)"
        case .blockstreamInfoTestnetOnion:   return "blockstream.info (testnet, Tor)"
        case .mempoolEmzyDeMainnet:          return "mempool.emzy.de"
        case .mempoolEmzyDeMainnetOnion:     return "mempool.emzy.de (Tor)"
        case .mempoolBisqServicesMainnet:    return "mempool.bisq.services"
        case .mempoolBisqServicesMainnetOnion: return "mempool.bisq.services (Tor)"
        }
    }

    /// Longer description shown under the preset name — explains the
    /// operator and any rate-limit or privacy posture the user should know.
    var subtitle: String {
        switch self {
        case .mempoolSpaceMainnet, .mempoolSpaceTestnet,
             .mempoolSpaceTestnet4, .mempoolSpaceSignet,
             .mempoolSpaceMainnetOnion, .mempoolSpaceTestnetOnion,
             .mempoolSpaceTestnet4Onion, .mempoolSpaceSignetOnion:
            return "Community-run, rate-limited, self-hostable."
        case .blockstreamInfoMainnet, .blockstreamInfoTestnet,
             .blockstreamInfoMainnetOnion, .blockstreamInfoTestnetOnion:
            return "Run by Blockstream. Rate-limited."
        case .mempoolEmzyDeMainnet, .mempoolEmzyDeMainnetOnion:
            return "Community mirror operated by Emzy."
        case .mempoolBisqServicesMainnet, .mempoolBisqServicesMainnetOnion:
            return "Mirror operated by the Bisq DAO."
        }
    }

    /// Base URL for the API root — the same URL passed to
    /// ``EsploraBlockSource/init(endpoint:urlSession:minimumInterRequestDelay:maximumRetries:baseRetryDelay:)``.
    var url: URL {
        switch self {
        // mempool.space clearnet
        case .mempoolSpaceMainnet:    return URL(string: "https://mempool.space/api")!
        case .mempoolSpaceTestnet:    return URL(string: "https://mempool.space/testnet/api")!
        case .mempoolSpaceTestnet4:   return URL(string: "https://mempool.space/testnet4/api")!
        case .mempoolSpaceSignet:     return URL(string: "https://mempool.space/signet/api")!
        // mempool.space onion
        case .mempoolSpaceMainnetOnion:
            return URL(string: "http://mempoolhqx4isw62xs7abwphsq7ldayuidyx2v2oethdhhj6mlo2r6ad.onion/api")!
        case .mempoolSpaceTestnetOnion:
            return URL(string: "http://mempoolhqx4isw62xs7abwphsq7ldayuidyx2v2oethdhhj6mlo2r6ad.onion/testnet/api")!
        case .mempoolSpaceTestnet4Onion:
            return URL(string: "http://mempoolhqx4isw62xs7abwphsq7ldayuidyx2v2oethdhhj6mlo2r6ad.onion/testnet4/api")!
        case .mempoolSpaceSignetOnion:
            return URL(string: "http://mempoolhqx4isw62xs7abwphsq7ldayuidyx2v2oethdhhj6mlo2r6ad.onion/signet/api")!
        // blockstream.info clearnet
        case .blockstreamInfoMainnet: return URL(string: "https://blockstream.info/api")!
        case .blockstreamInfoTestnet: return URL(string: "https://blockstream.info/testnet/api")!
        // blockstream.info onion
        case .blockstreamInfoMainnetOnion:
            return URL(string: "http://explorerzydxu5ecjrkwceayqybizmpjjznk5izmitf2modhcusuqlid.onion/api")!
        case .blockstreamInfoTestnetOnion:
            return URL(string: "http://explorerzydxu5ecjrkwceayqybizmpjjznk5izmitf2modhcusuqlid.onion/testnet/api")!
        // Community mirrors (mainnet only)
        case .mempoolEmzyDeMainnet:
            return URL(string: "https://mempool.emzy.de/api")!
        case .mempoolEmzyDeMainnetOnion:
            return URL(string: "http://mempool4t6mypeemozyterviq3i5de4kpoua65r3qkn5i3kknu5l2cad.onion/api")!
        case .mempoolBisqServicesMainnet:
            return URL(string: "https://mempool.bisq.services/api")!
        case .mempoolBisqServicesMainnetOnion:
            return URL(string: "http://mempoolcutehjtynu4k4rd746acmssvj2vz4jbz4setb72clbpx2dfqd.onion/api")!
        }
    }

    /// The ``ChainType`` this preset serves.
    var chainType: ChainType {
        switch self {
        case .mempoolSpaceMainnet, .mempoolSpaceMainnetOnion,
             .blockstreamInfoMainnet, .blockstreamInfoMainnetOnion,
             .mempoolEmzyDeMainnet, .mempoolEmzyDeMainnetOnion,
             .mempoolBisqServicesMainnet, .mempoolBisqServicesMainnetOnion:
            return .mainnet
        case .mempoolSpaceTestnet, .mempoolSpaceTestnetOnion,
             .blockstreamInfoTestnet, .blockstreamInfoTestnetOnion:
            return .testnet
        case .mempoolSpaceTestnet4, .mempoolSpaceTestnet4Onion:
            return .testnet4
        case .mempoolSpaceSignet, .mempoolSpaceSignetOnion:
            return .signet
        }
    }

    /// `true` when the preset's host is a `.onion` v3 service and the
    /// URL will not resolve over clearnet DNS. Callers driving the UI
    /// should hide these unless the user has Tor routing enabled.
    var requiresTor: Bool {
        url.host?.hasSuffix(".onion") ?? false
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

    /// Presets that serve the given chain AND are reachable given the
    /// user's Tor-routing choice. When `torRouting` is `false`, `.onion`
    /// presets are dropped because their hosts won't resolve over
    /// clearnet DNS.
    ///
    /// - Parameters:
    ///   - chainType: Chain to filter by.
    ///   - torRouting: Whether the caller has Tor routing enabled.
    /// - Returns: Presets in declaration order that are compatible with
    ///   both filters.
    static func presets(for chainType: ChainType, torRouting: Bool) -> [BlockSourcePreset] {
        presets(for: chainType).filter { torRouting || !$0.requiresTor }
    }
}
