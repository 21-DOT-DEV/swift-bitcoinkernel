import Foundation

public struct BlockHeader: Codable {
    public let hash: String
    public let confirmations: Int
    public let height: Int
    public let version: Int
    public let versionHex: String
    public let merkleroot: String
    public let time: Int
    public let mediantime: Int
    public let nonce: Int
    public let bits: String
    public let difficulty: Double
    public let chainwork: String
    public let nTx: Int
    public let previousblockhash: String?
    public let nextblockhash: String?
}