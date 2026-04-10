//
//  TxSpendingPrevout.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Result item from `gettxspendingprevout` (v24+).
public struct TxSpendingPrevout: Codable, Sendable, Equatable {
    /// The transaction id of the checked output.
    public let txid: String

    /// The output index.
    public let vout: Int

    /// The transaction id of the mempool transaction spending this output (if any).
    public let spendingtxid: String?
}
