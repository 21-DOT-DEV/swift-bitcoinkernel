//
//  BlockStats.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Per-block statistics from `getblockstats`.
///
/// All amount fields are in **satoshis** (raw `Int64`), not BTC — confirmed
/// from Bitcoin Core source (`GetBlockSubsidy` and raw sats throughout).
public struct BlockStats: Codable, Sendable, Equatable {
    /// Average fee in the block, in satoshis.
    public let avgfee: Int64
    /// Average fee rate in the block, in satoshis per virtual byte.
    public let avgfeerate: Int64
    /// Average transaction size.
    public let avgtxsize: Int
    /// The block hash (useful for detecting reorgs).
    public let blockhash: String
    /// The block height.
    public let height: Int
    /// The number of inputs (excluding coinbase).
    public let ins: Int
    /// Maximum fee in the block, in satoshis.
    public let maxfee: Int64
    /// Maximum fee rate in the block, in satoshis per virtual byte.
    public let maxfeerate: Int64
    /// Maximum transaction size.
    public let maxtxsize: Int
    /// Truncated median fee in the block, in satoshis.
    public let medianfee: Int64
    /// The block median time past.
    public let mediantime: UnixTimestamp
    /// Truncated median transaction size.
    public let mediantxsize: Int
    /// Minimum fee in the block, in satoshis.
    public let minfee: Int64
    /// Minimum fee rate in the block, in satoshis per virtual byte.
    public let minfeerate: Int64
    /// Minimum transaction size.
    public let mintxsize: Int
    /// The number of outputs.
    public let outs: Int
    /// The block subsidy, in satoshis.
    public let subsidy: Int64
    /// The block time.
    public let time: UnixTimestamp
    /// Total fees in the block, in satoshis.
    public let totalfee: Int64
    /// The number of transactions (including coinbase).
    public let txs: Int
    /// The increase/decrease in the number of unspent outputs (not discounting OP_RETURN and similar).
    public let utxoIncrease: Int
    /// The increase/decrease in the number of unspent outputs, not counting unspendables.
    public let utxoIncreaseActual: Int
    /// The increase/decrease in size for the UTXO index (not discounting OP_RETURN and similar).
    public let utxoSizeInc: Int
    /// The increase/decrease in size for the UTXO index, not counting unspendables.
    public let utxoSizeIncActual: Int
    /// Total size of all segwit transactions.
    public let swTotalSize: Int?
    /// Total weight of all segwit transactions.
    public let swTotalWeight: Int?
    /// The number of segwit transactions.
    public let swtxs: Int?
    /// Total amount in all outputs (excluding coinbase and thus reward), in satoshis.
    public let totalOut: Int64
    /// Total size of all non-coinbase transactions.
    public let totalSize: Int
    /// Total weight of all non-coinbase transactions.
    public let totalWeight: Int
    /// Fee rates at the 10th, 25th, 50th, 75th, and 90th percentile weight unit,
    /// in satoshis per virtual byte.
    public let feeratePercentiles: [Int64]?

    enum CodingKeys: String, CodingKey {
        case avgfee, avgfeerate, avgtxsize, blockhash, height, ins
        case maxfee, maxfeerate, maxtxsize, medianfee, mediantime, mediantxsize
        case minfee, minfeerate, mintxsize, outs, subsidy, time
        case totalfee, txs, swtxs
        case utxoIncrease = "utxo_increase"
        case utxoIncreaseActual = "utxo_increase_actual"
        case utxoSizeInc = "utxo_size_inc"
        case utxoSizeIncActual = "utxo_size_inc_actual"
        case swTotalSize = "swtotal_size"
        case swTotalWeight = "swtotal_weight"
        case totalOut = "total_out"
        case totalSize = "total_size"
        case totalWeight = "total_weight"
        case feeratePercentiles = "feerate_percentiles"
    }
}
