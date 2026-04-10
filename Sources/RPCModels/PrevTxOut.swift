//
//  PrevTxOut.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Previous transaction output description for `signrawtransactionwithkey`.
///
/// Encodable request type — not decoded from responses.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct PrevTxOut: Encodable, Sendable {
    public let txid: String
    public let vout: Int
    public let scriptPubKey: String
    public let redeemScript: String?
    public let witnessScript: String?
    public let amount: BTCAmount?

    public init(
        txid: String,
        vout: Int,
        scriptPubKey: String,
        redeemScript: String? = nil,
        witnessScript: String? = nil,
        amount: BTCAmount? = nil
    ) {
        self.txid = txid
        self.vout = vout
        self.scriptPubKey = scriptPubKey
        self.redeemScript = redeemScript
        self.witnessScript = witnessScript
        self.amount = amount
    }
}
