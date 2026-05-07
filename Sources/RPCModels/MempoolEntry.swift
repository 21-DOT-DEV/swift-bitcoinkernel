//
//  MempoolEntry.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// A single mempool transaction entry from `getmempoolentry` or verbose mempool RPCs.
///
/// Deprecated top-level fee fields (`fee`, `modifiedfee`, `ancestorfees`,
/// `descendantfees`) are included as optionals for backward compatibility.
/// Prefer the structured `fees` object instead.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct MempoolEntry: Codable, Sendable, Equatable {
    /// Virtual transaction size (BIP 141).
    public let vsize: Int

    /// Transaction weight (BIP 141).
    public let weight: Int

    /// Local time transaction entered pool.
    public let time: UnixTimestamp

    /// Block height when transaction entered pool.
    public let height: Int

    /// Number of in-mempool descendant transactions (including this one).
    public let descendantcount: Int

    /// Virtual transaction size of in-mempool descendants (including this one).
    public let descendantsize: Int

    /// Number of in-mempool ancestor transactions (including this one).
    public let ancestorcount: Int

    /// Virtual transaction size of in-mempool ancestors (including this one).
    public let ancestorsize: Int

    /// Hash of serialized transaction, including witness data.
    public let wtxid: String

    /// Structured fee breakdown (preferred over deprecated top-level fields).
    public let fees: MempoolFees

    /// Unconfirmed transactions used as inputs for this transaction (txids).
    public let depends: [String]

    /// Unconfirmed transactions spending outputs from this transaction (txids).
    public let spentby: [String]

    /// Whether this transaction signals BIP 125 replace-by-fee.
    public let bip125Replaceable: Bool

    /// Whether this transaction is currently unbroadcast.
    public let unbroadcast: Bool

    // MARK: - Deprecated fields (optional)

    /// Transaction fee in BTC (deprecated — use `fees.base`).
    public let fee: BTCAmount?

    /// Transaction fee with fee deltas in BTC (deprecated — use `fees.modified`).
    public let modifiedfee: BTCAmount?

    /// Modified fees of in-mempool descendants in satoshis (deprecated — use `fees.descendant`).
    public let descendantfees: Int64?

    /// Modified fees of in-mempool ancestors in satoshis (deprecated — use `fees.ancestor`).
    public let ancestorfees: Int64?

    enum CodingKeys: String, CodingKey {
        case vsize, weight, time, height
        case descendantcount, descendantsize, ancestorcount, ancestorsize
        case wtxid, fees, depends, spentby, unbroadcast
        case fee, modifiedfee, descendantfees, ancestorfees
        case bip125Replaceable = "bip125-replaceable"
    }
}
