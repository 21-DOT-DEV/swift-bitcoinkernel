import Foundation

public struct BlockStats: Codable {
    public let avgfee: Int
    public let avgfeerate: Int
    public let avgtxsize: Int
    public let blockhash: String
    public let feerate_percentiles: [Int]
    public let height: Int
    public let ins: Int
    public let maxfee: Int
    public let maxfeerate: Int
    public let maxtxsize: Int
    public let medianfee: Int
    public let mediantime: Int
    public let mediantxsize: Int
    public let minfee: Int
    public let minfeerate: Int
    public let mintxsize: Int
    public let outs: Int
    public let subsidy: Int
    public let swtotal_size: Int
    public let swtotal_weight: Int
    public let swtxs: Int
    public let time: Int
    public let total_out: Int
    public let total_size: Int
    public let total_weight: Int
    public let totalfee: Int
    public let txs: Int
    public let utxo_increase: Int
    public let utxo_size_inc: Int
}