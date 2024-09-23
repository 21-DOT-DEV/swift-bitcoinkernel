import Foundation

public struct UTXOSetInfo: Codable {
    public let height: Int
    public let bestblock: String
    public let transactions: Int
    public let txouts: Int
    public let bogosize: Int
    public let hash_serialized_2: String?
    public let disk_size: Int
    public let total_amount: Double
    
    public init(height: Int, bestblock: String, transactions: Int, txouts: Int, bogosize: Int, hash_serialized_2: String?, disk_size: Int, total_amount: Double) {
        self.height = height
        self.bestblock = bestblock
        self.transactions = transactions
        self.txouts = txouts
        self.bogosize = bogosize
        self.hash_serialized_2 = hash_serialized_2
        self.disk_size = disk_size
        self.total_amount = total_amount
    }
}