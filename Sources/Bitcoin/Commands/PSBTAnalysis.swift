import Foundation

public struct PSBTAnalysis: Codable {
    public struct InputAnalysis: Codable {
        public let hasUTXO: Bool
        public let isFinal: Bool
        public let missing: MissingData?
        public let next: String?
        
        enum CodingKeys: String, CodingKey {
            case hasUTXO = "has_utxo"
            case isFinal = "is_final"
            case missing, next
        }
    }
    
    public struct MissingData: Codable {
        public let pubkeys: [String]?
        public let signatures: [String]?
        public let redeemscript: String?
        public let witnessscript: String?
    }
    
    public let inputs: [InputAnalysis]
    public let estimatedVsize: Int?
    public let estimatedFeerate: Double?
    public let fee: Double?
    public let next: String
    public let error: String?
    
    enum CodingKeys: String, CodingKey {
        case inputs
        case estimatedVsize = "estimated_vsize"
        case estimatedFeerate = "estimated_feerate"
        case fee, next, error
    }
}