//
//  PrevTxOut.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Previous transaction output description for `signrawtransactionwithkey`.
///
/// Encodable request type — not decoded from responses.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct PrevTxOut: Encodable, Sendable, Equatable {
    /// The transaction id.
    public let txid: String
    /// The output number.
    public let vout: Int
    /// The output script.
    public let scriptPubKey: String
    /// The redeem script (required for P2SH).
    public let redeemScript: String?
    /// The witness script (required for P2WSH or P2SH-P2WSH).
    public let witnessScript: String?
    /// The amount spent (required for Segwit inputs).
    public let amount: BTCAmount?

    /// Creates a previous transaction output description.
    ///
    /// - Parameters:
    ///   - txid: The transaction id.
    ///   - vout: The output number.
    ///   - scriptPubKey: The output script.
    ///   - redeemScript: The redeem script (required for P2SH).
    ///   - witnessScript: The witness script (required for P2WSH or P2SH-P2WSH).
    ///   - amount: The amount spent (required for Segwit inputs).
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
