//
//  BitcoinConfig+NetworkScoped.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

// MARK: - Regtest-Only Options

extension BitcoinConfig where N == Regtest {

    /// Allow mining of blocks with near-zero difficulty (regtest only).
    public func fastPrune(_ enabled: Bool = true) -> Self {
        appending("fastprune", bool: enabled)
    }

    /// Activate a particular soft fork at a given height.
    ///
    /// Format: `"name@height"` (e.g. `"segwit@0"`).
    public func testActivationHeight(_ param: String) -> Self {
        appending("testactivationheight", param)
    }

    /// Override version bits parameters for named soft forks.
    ///
    /// Format: `"deployment:start:end"`.
    public func vbParams(_ params: String) -> Self {
        appending("vbparams", params)
    }

    /// Accept stale fee estimates (useful in regtest where blocks arrive on
    /// demand and the fee estimator has no data).
    ///
    /// This is a debug-category option pulled into Phase 1 because it is
    /// regtest-only and demonstrates the phantom-type constraint.
    public func acceptStaleFeeEstimates(_ enabled: Bool = true) -> Self {
        appending("acceptstalefeeestimates", bool: enabled)
    }
}

// MARK: - Signet-Only Options

extension BitcoinConfig where N == Signet {

    /// Override the default signet challenge script.
    public func signetChallenge(_ script: String) -> Self {
        appending("signetchallenge", script)
    }

    /// Specify a seed node for the signet network.
    ///
    /// Call multiple times to specify multiple seed nodes.
    public func signetSeedNode(_ host: String) -> Self {
        appending("signetseednode", host)
    }
}
