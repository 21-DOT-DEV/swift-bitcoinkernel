import Foundation

public struct RawMempool: Codable {
    public let txids: [String]?
    public let mempool_sequence: Int?
    public let transactions: [String: MempoolEntry]?
    
    public init(txids: [String]? = nil, mempool_sequence: Int? = nil, transactions: [String: MempoolEntry]? = nil) {
        self.txids = txids
        self.mempool_sequence = mempool_sequence
        self.transactions = transactions
    }
}