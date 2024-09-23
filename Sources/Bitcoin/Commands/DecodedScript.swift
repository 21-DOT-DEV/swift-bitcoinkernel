import Foundation

public struct DecodedScript: Codable {
    public let asm: String
    public let type: String
    public let reqSigs: Int?
    public let addresses: [String]?
    public let p2sh: String?
    public let segwit: SegwitInfo?
    
    public struct SegwitInfo: Codable {
        public let asm: String
        public let hex: String
        public let type: String
        public let reqSigs: Int
        public let addresses: [String]
        public let p2shSegwit: String
        
        enum CodingKeys: String, CodingKey {
            case asm, hex, type, reqSigs, addresses
            case p2shSegwit = "p2sh-segwit"
        }
    }
}