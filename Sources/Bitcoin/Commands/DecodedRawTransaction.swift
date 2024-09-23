import Foundation

public struct DecodedRawTransaction: Codable {
    public let txid: String
    public let hash: String
    public let size: Int
    public let vsize: Int
    public let weight: Int
    public let version: Int
    public let locktime: Int
    public let vin: [Input]
    public let vout: [Output]
    
    public struct Input: Codable {
        public let txid: String
        public let vout: Int
        public let scriptSig: Script
        public let txinwitness: [String]?
        public let sequence: Int
    }
    
    public struct Output: Codable {
        public let value: Double
        public let n: Int
        public let scriptPubKey: ScriptPubKey
    }
    
    public struct Script: Codable {
        public let asm: String
        public let hex: String
    }
    
    public struct ScriptPubKey: Codable {
        public let asm: String
        public let hex: String
        public let reqSigs: Int?
        public let type: String
        public let addresses: [String]?
    }
}