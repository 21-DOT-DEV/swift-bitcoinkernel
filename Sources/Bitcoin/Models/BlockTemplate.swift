//
//  BlockTemplate.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Block template data from `getblocktemplate` (BIP 22/23/9/145).
///
/// Contains everything needed to construct a candidate block for mining.
/// Fee and coinbase value fields are in **satoshis** (not `BTCAmount`).
///
/// - Note: Targets Bitcoin Core v31.x.
public struct BlockTemplate: Codable, Sendable, Equatable {
    /// The preferred block version.
    public let version: Int

    /// Specific block rules that are to be enforced (BIP 9).
    public let rules: [String]

    /// Set of pending, supported versionbit (BIP 9) softfork deployments.
    /// Keys are rule names, values are bit numbers.
    public let vbavailable: [String: Int]

    /// Bit mask of versionbits the server requires set in submissions.
    public let vbrequired: Int

    /// The hash of the current highest block.
    public let previousblockhash: String

    /// Non-coinbase transactions that should be included in the next block.
    public let transactions: [BlockTemplateTransaction]

    /// Data that should be included in the coinbase's scriptSig content.
    public let coinbaseaux: [String: String]

    /// Maximum allowable input to coinbase transaction, including the generation
    /// award and transaction fees (in satoshis).
    public let coinbasevalue: Int64

    /// An id to include with a request to longpoll on an update to this template.
    public let longpollid: String

    /// The hash target.
    public let target: String

    /// The minimum timestamp appropriate for the next block time.
    public let mintime: UnixTimestamp

    /// List of ways the block template may be changed.
    public let mutable: [String]

    /// A range of valid nonces (hex).
    public let noncerange: String

    /// Limit of sigops in blocks.
    public let sigoplimit: Int

    /// Limit of block size.
    public let sizelimit: Int

    /// Limit of block weight.
    public let weightlimit: Int

    /// Current timestamp.
    public let curtime: UnixTimestamp

    /// Compressed target of next block.
    public let bits: String

    /// The height of the next block.
    public let height: Int

    /// A valid witness commitment for the unmodified block template (optional).
    public let defaultWitnessCommitment: String?

    enum CodingKeys: String, CodingKey {
        case version, rules, vbavailable, vbrequired, previousblockhash
        case transactions, coinbaseaux, coinbasevalue, longpollid, target
        case mintime, mutable, noncerange, sigoplimit, sizelimit, weightlimit
        case curtime, bits, height
        case defaultWitnessCommitment = "default_witness_commitment"
    }
}

/// A transaction entry within a block template.
///
/// All fee/sigop fields are in **satoshis** or raw counts (not `BTCAmount`).
public struct BlockTemplateTransaction: Codable, Sendable, Equatable {
    /// Transaction data encoded in hexadecimal (byte-for-byte).
    public let data: String

    /// Transaction id encoded in little-endian hexadecimal.
    public let txid: String

    /// Hash encoded in little-endian hexadecimal (including witness data).
    public let hash: String

    /// Transactions before this one (by 1-based index in `transactions` list)
    /// that must be present in the final block if this one is.
    public let depends: [Int]

    /// Difference in value between transaction inputs and outputs (in satoshis).
    /// For coinbase transactions, this is a negative number of the total collected
    /// block fees. May be absent if fee is unknown.
    public let fee: Int64?

    /// Total SigOps cost, as counted for purposes of block limits.
    /// May be absent if sigop cost is unknown.
    public let sigops: Int?

    /// Total transaction weight, as counted for purposes of block limits.
    public let weight: Int
}

/// Request parameters for `getblocktemplate` (BIP 22/23).
///
/// The `rules` array is **required** by Core v31.x — omitting it returns an error.
/// At minimum, include `["segwit"]`.
public struct BlockTemplateRequest: Encodable, Sendable {
    /// Must be "template" (default) or "proposal" (see BIP 23), or omitted.
    public let mode: String?

    /// Client-side supported features (e.g., "longpoll", "coinbasevalue", "proposal").
    public let capabilities: [String]?

    /// Client-side supported softfork deployment rules. Required: `["segwit"]` minimum.
    public let rules: [String]

    /// For long-polling (template mode only).
    public let longpollid: String?

    /// Block hex (proposal mode only).
    public let data: String?

    /// Creates a request for `getblocktemplate`.
    ///
    /// - Parameters:
    ///   - rules: Client-side supported softfork deployment rules. Required by Core v31.x; defaults to `["segwit"]`.
    ///   - mode: `"template"` (default) or `"proposal"` (BIP 23). `nil` lets the server pick.
    ///   - capabilities: Client-side supported features (e.g., `"longpoll"`, `"coinbasevalue"`, `"proposal"`).
    ///   - longpollid: Long-poll identifier returned by a previous template (template mode only).
    ///   - data: Block hex to submit for validation (proposal mode only).
    public init(
        rules: [String] = ["segwit"],
        mode: String? = nil,
        capabilities: [String]? = nil,
        longpollid: String? = nil,
        data: String? = nil
    ) {
        self.mode = mode
        self.capabilities = capabilities
        self.rules = rules
        self.longpollid = longpollid
        self.data = data
    }
}
