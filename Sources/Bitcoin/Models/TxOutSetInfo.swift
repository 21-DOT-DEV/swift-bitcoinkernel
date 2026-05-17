//
//  TxOutSetInfo.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// UTXO set statistics from `gettxoutsetinfo`.
public struct TxOutSetInfo: Codable, Sendable, Equatable {
    /// The block height of the snapshot.
    public let height: Int

    /// The best block hash.
    public let bestblock: String

    /// The number of unspent transaction outputs.
    public let txouts: Int

    /// The serialized size of the UTXO set in bytes.
    public let bogosize: Int64

    /// The hash of the UTXO set (depends on `hash_type` param).
    public let hashSerialized2: String?

    /// The hash of the UTXO set (muhash).
    public let muhash: String?

    /// The total amount of all UTXOs in BTC.
    public let totalAmount: BTCAmount

    /// The number of transactions with unspent outputs.
    public let transactions: Int

    /// Disk size of the UTXO set in bytes.
    public let diskSize: Int64

    enum CodingKeys: String, CodingKey {
        case height, bestblock, txouts, bogosize
        case hashSerialized2 = "hash_serialized_2"
        case muhash, transactions
        case totalAmount = "total_amount"
        case diskSize = "disk_size"
    }
}
