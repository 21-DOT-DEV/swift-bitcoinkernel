import Foundation

public struct ChainTxStats: Codable {
    public let time: Int
    public let txcount: Int
    public let window_final_block_hash: String
    public let window_final_block_height: Int
    public let window_block_count: Int
    public let window_tx_count: Int?
    public let window_interval: Int?
    public let txrate: Double?
    
    public init(time: Int, txcount: Int, window_final_block_hash: String, window_final_block_height: Int, window_block_count: Int, window_tx_count: Int?, window_interval: Int?, txrate: Double?) {
        self.time = time
        self.txcount = txcount
        self.window_final_block_hash = window_final_block_hash
        self.window_final_block_height = window_final_block_height
        self.window_block_count = window_block_count
        self.window_tx_count = window_tx_count
        self.window_interval = window_interval
        self.txrate = txrate
    }
}