import Foundation

public struct ScanObject: Codable {
    public let desc: String
    public let range: RangeValue?
    
    public enum RangeValue: Codable {
        case single(Int)
        case range(start: Int, end: Int)
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let singleValue = try? container.decode(Int.self) {
                self = .single(singleValue)
            } else if let rangeArray = try? container.decode([Int].self), rangeArray.count == 2 {
                self = .range(start: rangeArray[0], end: rangeArray[1])
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid range value")
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .single(let value):
                try container.encode(value)
            case .range(let start, let end):
                try container.encode([start, end])
            }
        }
    }
}

public struct ScanTxOutSetResult: Codable {
    public let success: Bool
    public let txouts: Int
    public let height: Int
    public let bestblock: String
    public let unspents: [Unspent]
    public let total_amount: Double
    
    public struct Unspent: Codable {
        public let txid: String
        public let vout: Int
        public let scriptPubKey: String
        public let desc: String
        public let amount: Double
        public let height: Int
    }
}