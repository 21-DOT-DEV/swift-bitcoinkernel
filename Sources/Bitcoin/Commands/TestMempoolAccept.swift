import Foundation

public struct TestMempoolAcceptResult: Codable {
    public let txid: String
    public let allowed: Bool
    public let vsize: Int?
    public let fees: Fees?
    public let rejectReason: String?
    
    public struct Fees: Codable {
        public let base: Double
    }
    
    enum CodingKeys: String, CodingKey {
        case txid, allowed, vsize, fees
        case rejectReason = "reject-reason"
    }
}