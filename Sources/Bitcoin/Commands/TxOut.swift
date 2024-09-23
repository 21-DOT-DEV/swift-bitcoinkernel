import Foundation

public struct TxOut: Codable {
    public let bestblock: String
    public let confirmations: Int
    public let value: Double
    public let scriptPubKey: ScriptPubKey
    public let coinbase: Bool
    
    public struct ScriptPubKey: Codable {
        public let asm: String
        public let hex: String
        public let reqSigs: Int?
        public let type: String
        public let addresses: [String]?
    }
}