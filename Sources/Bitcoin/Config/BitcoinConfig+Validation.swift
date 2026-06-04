//
//  BitcoinConfig+Validation.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

// MARK: - ConfigError

/// A fatal conflict in a ``BitcoinConfig`` that prevents the daemon from
/// starting correctly.
public enum ConfigError: Error, Sendable, CustomStringConvertible, LocalizedError, CaseIterable, Equatable {
    /// `txindex=1` and `prune=<size>` are mutually exclusive.
    case txIndexWithPrune

    /// `coinstatsindex=1` and `prune=<size>` are mutually exclusive.
    case coinStatsIndexWithPrune

    /// `peerblockfilters=1` requires `blockfilterindex=1` to be set.
    case peerBlockFiltersWithoutIndex

    public var description: String {
        switch self {
        case .txIndexWithPrune:
            return "txindex=1 is incompatible with prune: remove one or the other."
        case .coinStatsIndexWithPrune:
            return "coinstatsindex=1 is incompatible with prune: remove one or the other."
        case .peerBlockFiltersWithoutIndex:
            return "peerblockfilters=1 requires blockfilterindex=1: add .blockFilterIndex(.all)."
        }
    }

    public var errorDescription: String? { description }
}

// MARK: - ConfigWarning

/// A non-fatal issue in a ``BitcoinConfig`` that may indicate misconfiguration.
public enum ConfigWarning: Sendable, CustomStringConvertible, CaseIterable, Equatable, Hashable {
    /// `rpcbind` is set but `rpcallowip` is not — Bitcoin Core ignores rpcbind
    /// unless at least one allowed IP is specified.
    case rpcBindWithoutAllowIP

    /// RPC options are configured but `server=0` — they will have no effect.
    case serverDisabledWithRPCOptions

    /// `blocksonly=1` is set alongside `maxmempool` — the mempool setting is
    /// irrelevant in blocks-only mode.
    case blocksOnlyWithMaxMempool

    /// `server=1` is set but neither `rpcauth` credentials nor an explicit
    /// `rpccookiefile` path are provided. Bitcoin Core will still generate a
    /// default cookie, but the warning helps catch configs where authentication
    /// was unintentionally omitted.
    case missingRPCAuth

    /// `connect=<host>` is set — peer discovery via `-addnode`, `-seednode`,
    /// and `-dnsseed` is disabled.
    case connectDisablesPeerDiscovery

    /// A wallet option is configured alongside `disablewallet=1` — the
    /// wallet option will have no effect.
    case walletOptionWithDisableWallet

    /// `maxuploadtarget` is set alongside `listen=1` — ensure the cap is high
    /// enough (≥ 100 MiB/day) to maintain adequate peer connectivity.
    case maxUploadTargetWithListen

    public var description: String {
        switch self {
        case .rpcBindWithoutAllowIP:
            return "rpcbind is set but rpcallowip is not — rpcbind has no effect without rpcallowip."
        case .serverDisabledWithRPCOptions:
            return "server=0 but RPC options are configured — they will have no effect."
        case .blocksOnlyWithMaxMempool:
            return "blocksonly=1 is set with maxmempool — mempool settings are ignored in blocks-only mode."
        case .missingRPCAuth:
            return "server=1 is set but no rpcauth or rpccookiefile was provided — clients will need the default cookie to connect."
        case .connectDisablesPeerDiscovery:
            return "connect= is set — addnode, seednode, and dnsseed have no effect in fixed-peer mode."
        case .walletOptionWithDisableWallet:
            return "disablewallet=1 is set but wallet options are also configured — they will have no effect."
        case .maxUploadTargetWithListen:
            return "maxuploadtarget is set with listen=1 — ensure the cap is ≥ 100 MiB/day for healthy peer connectivity."
        }
    }
}

// MARK: - validate()

extension BitcoinConfig {

    /// Validates the configuration for cross-field conflicts.
    ///
    /// Checks `ConfigFlags` in O(1) — no string parsing.
    ///
    /// - Returns: A (possibly empty) array of non-fatal warnings.
    /// - Throws: A ``ConfigError`` if a fatal conflict is detected.
    public func validate() throws(ConfigError) -> [ConfigWarning] {
        var warnings: [ConfigWarning] = []

        // Fatal errors — throw immediately
        if flags.contains(.txIndex) && flags.contains(.pruneSize) {
            throw .txIndexWithPrune
        }
        if flags.contains(.coinStatsIndex) && flags.contains(.pruneSize) {
            throw .coinStatsIndexWithPrune
        }
        if flags.contains(.peerBlockFilters) && !flags.contains(.blockFilterIndexAll) {
            throw .peerBlockFiltersWithoutIndex
        }

        // Non-fatal warnings
        if flags.contains(.rpcBind) && !flags.contains(.rpcAllowIP) {
            warnings.append(.rpcBindWithoutAllowIP)
        }
        if !flags.contains(.server) && (flags.contains(.rpcBind) || flags.contains(.rpcAuth) || flags.contains(.rpcAllowIP) || flags.contains(.rpcCookieFile)) {
            warnings.append(.serverDisabledWithRPCOptions)
        }
        if flags.contains(.blocksOnly) && flags.contains(.maxMempool) {
            warnings.append(.blocksOnlyWithMaxMempool)
        }
        if flags.contains(.server) && !flags.contains(.rpcAuth) && !flags.contains(.rpcCookieFile) {
            warnings.append(.missingRPCAuth)
        }
        if flags.contains(.connect) {
            warnings.append(.connectDisablesPeerDiscovery)
        }
        if flags.contains(.disableWallet) && flags.contains(.walletOption) {
            warnings.append(.walletOptionWithDisableWallet)
        }
        if flags.contains(.maxUploadTarget) && flags.contains(.listen) {
            warnings.append(.maxUploadTargetWithListen)
        }

        return warnings
    }
}
