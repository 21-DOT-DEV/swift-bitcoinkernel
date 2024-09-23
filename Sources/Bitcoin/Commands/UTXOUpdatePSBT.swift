import Foundation

public struct UTXOUpdatePSBTDescriptor: Codable {
    public let desc: String
    public let range: RangeValue?
    
    public enum RangeValue: Codable {
        case single(Int)
        case range(Int, Int)
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let singleValue = try? container.decode(Int.self) {
                self = .single(singleValue)
            } else if let rangeArray = try? container.decode([Int].self), rangeArray.count == 2 {
                self = .range(rangeArray[0], rangeArray[1])
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