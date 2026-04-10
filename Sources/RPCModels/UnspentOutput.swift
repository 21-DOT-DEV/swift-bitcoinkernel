//
//  UnspentOutput.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// An unspent transaction output from `listunspent`.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct UnspentOutput: Codable, Sendable, Equatable {
    /// The transaction id.
    public let txid: String

    /// The vout index.
    public let vout: Int

    /// The bitcoin address.
    public let address: String?

    /// The associated label.
    public let label: String?

    /// The script public key.
    public let scriptPubKey: String

    /// The amount in BTC.
    public let amount: BTCAmount

    /// The number of confirmations.
    public let confirmations: Int

    /// The redeem script (if any).
    public let redeemScript: String?

    /// The witness script (if any).
    public let witnessScript: String?

    /// Whether the output is spendable.
    public let spendable: Bool

    /// Whether the output is solvable.
    public let solvable: Bool

    /// The number of in-mempool ancestor transactions (if in mempool).
    public let ancestorcount: Int?

    /// The virtual transaction size of in-mempool ancestors (if in mempool).
    public let ancestorsize: Int?

    /// The total fees of in-mempool ancestors in satoshis (if in mempool).
    public let ancestorfees: Int64?

    /// Whether the output is considered reused (avoid_reuse wallets).
    public let reused: Bool?

    /// A descriptor for spending this output.
    public let desc: String?

    /// List of parent descriptors for the output script of this coin.
    public let parent_descs: [String]? // swiftlint:disable:this identifier_name

    /// Whether the output is safe to spend (unconfirmed from outside keys treated as unsafe).
    public let safe: Bool
}
