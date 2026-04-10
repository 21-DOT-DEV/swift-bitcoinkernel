//
//  BlockStats.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Per-block statistics from `getblockstats`.
///
/// All amount fields are in **satoshis** (raw `Int64`), not BTC — confirmed
/// from Bitcoin Core source (`GetBlockSubsidy` and raw sats throughout).
public struct BlockStats: Codable, Sendable, Equatable {
    public let avgfee: Int64
    public let avgfeerate: Int64
    public let avgtxsize: Int
    public let blockhash: String
    public let height: Int
    public let ins: Int
    public let maxfee: Int64
    public let maxfeerate: Int64
    public let maxtxsize: Int
    public let medianfee: Int64
    public let mediantime: UnixTimestamp
    public let mediantxsize: Int
    public let minfee: Int64
    public let minfeerate: Int64
    public let mintxsize: Int
    public let outs: Int
    public let subsidy: Int64
    public let time: UnixTimestamp
    public let totalfee: Int64
    public let txs: Int
    public let utxoIncrease: Int
    public let utxoIncreaseActual: Int
    public let utxoSizeInc: Int
    public let utxoSizeIncActual: Int
    public let swTotalSize: Int?
    public let swTotalWeight: Int?
    public let swtxs: Int?
    public let totalOut: Int64
    public let totalSize: Int
    public let totalWeight: Int
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
