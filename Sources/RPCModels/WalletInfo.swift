//
//  WalletInfo.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Wallet state information from `getwalletinfo`.
///
/// - Note: Targets Bitcoin Core v31.x.
/// - Note: The `scanning` field is omitted because it is polymorphic (`false` or `{duration, progress}`).
public struct WalletInfo: Codable, Sendable, Equatable {
    /// The wallet name.
    public let walletname: String
    /// The wallet version.
    public let walletversion: Int
    /// The database format (`bdb` or `sqlite`).
    public let format: String
    /// The total number of transactions in the wallet.
    public let txcount: Int

    /// How many new keys are pre-generated (external keys only).
    public let keypoolsize: Int?

    /// Pre-generated internal keys (for change outputs).
    public let keypoolsize_hd_internal: Int? // swiftlint:disable:this identifier_name

    /// UNIX epoch time until wallet is unlocked (passphrase-encrypted wallets only).
    public let unlocked_until: Int64? // swiftlint:disable:this identifier_name

    /// False if private keys are disabled (watch-only wallet).
    public let private_keys_enabled: Bool // swiftlint:disable:this identifier_name

    /// Whether this wallet tracks clean/dirty coins for reuse avoidance.
    public let avoid_reuse: Bool // swiftlint:disable:this identifier_name

    /// Whether this wallet uses descriptors for output script management.
    public let descriptors: Bool

    /// Whether this wallet is configured to use an external signer (e.g. hardware wallet).
    public let external_signer: Bool // swiftlint:disable:this identifier_name

    /// Whether this wallet intentionally contains no keys, scripts, or descriptors.
    public let blank: Bool

    /// The start time for block scanning (absent if unknown).
    public let birthtime: Int64?

    /// The flags currently set on the wallet.
    public let flags: [String]

    /// The last block processed by the wallet.
    public let lastprocessedblock: LastProcessedBlock
}
