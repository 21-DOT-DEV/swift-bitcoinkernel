import Foundation

public struct BlockTemplate: Codable {
    public struct Transaction: Codable {
        public let data: String
        public let txid: String
        public let hash: String
        public let depends: [Int]
        public let fee: Int?
        public let sigops: Int?
        public let weight: Int
    }
    
    public let version: Int
    public let rules: [String]
    public let vbavailable: [String: Int]
    public let vbrequired: Int
    public let previousblockhash: String
    public let transactions: [Transaction]
    public let coinbaseaux: [String: String]
    public let coinbasevalue: Int
    public let longpollid: String
    public let target: String
    public let mintime: Int
    public let mutable: [String]
    public let noncerange: String
    public let sigoplimit: Int
    public let sizelimit: Int
    public let weightlimit: Int
    public let curtime: Int
    public let bits: String
    public let height: Int
    public let default_witness_commitment: String?
}

public struct BlockTemplateRequest: Codable {
    public let mode: String?
    public let capabilities: [String]?
    public let rules: [String]
    
    public init(mode: String? = nil, capabilities: [String]? = nil, rules: [String]) {
        self.mode = mode
        self.capabilities = capabilities
        self.rules = rules
    }
}