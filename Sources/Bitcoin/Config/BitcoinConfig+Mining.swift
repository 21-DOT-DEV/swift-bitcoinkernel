//
//  BitcoinConfig+Mining.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

// MARK: - Mining Options

extension BitcoinConfig {

    /// Minimum fee rate for transactions to be included in block templates (BTC/kvB).
    public func blockMinTxFee(_ rate: FeeRate) -> Self {
        appending("blockmintxfee", rate)
    }

    /// Maximum block weight for mined blocks in weight units (default 3,996,000).
    ///
    /// Must not exceed the consensus limit of 4,000,000 weight units.
    public func blockMaxWeight(_ units: UInt) -> Self {
        appending("blockmaxweight", min(4_000_000, units))
    }

    /// Maximum block size for legacy (pre-segwit) block templates in bytes.
    public func blockMaxSize(_ bytes: UInt) -> Self {
        appending("blockmaxsize", bytes)
    }
}
