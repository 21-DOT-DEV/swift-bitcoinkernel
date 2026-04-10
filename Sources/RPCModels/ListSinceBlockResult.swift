//
//  ListSinceBlockResult.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
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
    public let address: String?
    public let category: String
    public let amount: BTCAmount
    public let vout: Int
    public let fee: BTCAmount?
    public let confirmations: Int

    /// Only present if the transaction's only input is a coinbase one.
    public let generated: Bool?

    /// Whether we consider the transaction trusted and safe to spend from (only for 0-conf).
    public let trusted: Bool?

    public let blockhash: String?
    public let blockheight: Int?

    /// The index of the transaction in the block.
    public let blockindex: Int?

    public let blocktime: UnixTimestamp?
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

    public let time: UnixTimestamp
    public let timereceived: UnixTimestamp
    public let label: String?
    public let comment: String?
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
