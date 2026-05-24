//
//  WalletBalances.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Balance information from `getbalances`.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct WalletBalances: Codable, Sendable, Equatable {
    /// Balances from outputs the wallet can sign.
    public let mine: WalletBalanceDetail

    /// The last block processed by the wallet.
    public let lastprocessedblock: LastProcessedBlock
}

/// Balance breakdown for a wallet category (mine or watchonly).
public struct WalletBalanceDetail: Codable, Sendable, Equatable {
    /// Trusted balance (wallet-created or confirmed outputs).
    public let trusted: BTCAmount

    /// Untrusted pending balance (others' outputs in mempool).
    public let untrusted_pending: BTCAmount // swiftlint:disable:this identifier_name

    /// Balance from immature coinbase outputs.
    public let immature: BTCAmount

    /// Balance from previously-spent addresses (only if avoid_reuse is set).
    public let used: BTCAmount?
}
