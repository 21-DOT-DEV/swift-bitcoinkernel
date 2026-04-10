//
//  ScanTxOutResult.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Result from `scantxoutset` (action=start).
public struct ScanTxOutResult: Codable, Sendable, Equatable {
    /// Whether the scan completed successfully.
    public let success: Bool

    /// The number of unspent outputs scanned.
    public let txouts: Int

    /// The current block height when scan completed.
    public let height: Int

    /// The best block hash when scan completed.
    public let bestblock: String

    /// The matching UTXOs.
    public let unspents: [ScanTxOutUnspent]

    /// The total amount of all matching UTXOs.
    public let totalAmount: BTCAmount

    enum CodingKeys: String, CodingKey {
        case success, txouts, height, bestblock, unspents
        case totalAmount = "total_amount"
    }
}

/// An individual unspent output from `scantxoutset`.
public struct ScanTxOutUnspent: Codable, Sendable, Equatable {
    /// The transaction id.
    public let txid: String

    /// The output index.
    public let vout: Int

    /// The script pubkey (hex).
    public let scriptPubKey: String

    /// The matching descriptor.
    public let desc: String

    /// The amount in BTC.
    public let amount: BTCAmount

    /// Whether this is a coinbase output.
    public let coinbase: Bool

    /// The block height containing this output.
    public let height: Int
}
