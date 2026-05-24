//
//  ListSinceBlockResult.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Result of `listsinceblock`.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct ListSinceBlockResult: Codable, Sendable, Equatable {
    /// The transactions since the given block.
    public let transactions: [SinceBlockTransaction]

    /// Removed transactions (due to reorgs), if include_removed is set.
    public let removed: [SinceBlockTransaction]?

    /// The hash of the block at the requested depth.
    public let lastblock: String
}

/// A transaction from `listsinceblock` or `listtransactions`.
public struct SinceBlockTransaction: Codable, Sendable, Equatable {
    /// The bitcoin address involved.
    public let address: String?
    /// The transaction category (`send`, `receive`, `generate`, `immature`, or `orphan`).
    public let category: String
    /// The amount in BTC.
    public let amount: BTCAmount
    /// The vout index.
    public let vout: Int
    /// The fee in BTC (negative, only for `send` category).
    public let fee: BTCAmount?
    /// The number of confirmations for the transaction.
    public let confirmations: Int

    /// Only present if the transaction's only input is a coinbase one.
    public let generated: Bool?

    /// Whether we consider the transaction trusted and safe to spend from (only for 0-conf).
    public let trusted: Bool?

    /// The block hash containing the transaction.
    public let blockhash: String?
    /// The block height containing the transaction.
    public let blockheight: Int?

    /// The index of the transaction in the block.
    public let blockindex: Int?

    /// The block time in seconds since epoch.
    public let blocktime: UnixTimestamp?
    /// The transaction id.
    public let txid: String

    /// The witness transaction id.
    public let wtxid: String?

    /// Confirmed transactions that conflict with this transaction.
    public let walletconflicts: [String]?

    /// Whether this output was replaced by BIP 125.
    public let replaced_by_txid: String? // swiftlint:disable:this identifier_name

    /// Whether this output replaces another.
    public let replaces_txid: String? // swiftlint:disable:this identifier_name

    /// Transactions in the mempool that directly conflict with this transaction or an ancestor.
    public let mempoolconflicts: [String]?

    /// If a comment-to is associated with the transaction.
    public let to: String?

    /// The transaction time in seconds since epoch.
    public let time: UnixTimestamp
    /// The time received in seconds since epoch.
    public let timereceived: UnixTimestamp
    /// A label for the address.
    public let label: String?
    /// Comment associated with the transaction.
    public let comment: String?
    /// Whether the output is considered abandoned.
    public let abandoned: Bool?

    /// Whether this transaction signals BIP125 replaceability ("yes", "no", or "unknown").
    public let bip125Replaceable: String? // swiftlint:disable:this identifier_name

    /// List of parent descriptors for the output script (only for received).
    public let parent_descs: [String]? // swiftlint:disable:this identifier_name

    enum CodingKeys: String, CodingKey {
        case address, category, amount, vout, fee, confirmations
        case generated, trusted, blockhash, blockheight, blockindex, blocktime
        case txid, wtxid, walletconflicts
        case replaced_by_txid, replaces_txid // swiftlint:disable:this identifier_name
        case mempoolconflicts, to, time, timereceived
        case label, comment, abandoned
        case parent_descs // swiftlint:disable:this identifier_name
        case bip125Replaceable = "bip125-replaceable"
    }
}
