import Foundation

public struct Block: Codable {
    public let hash: String
    public let confirmations: Int
    public let size: Int
    public let strippedsize: Int
    public let weight: Int
    public let height: Int
    public let version: Int
    public let versionHex: String
    public let merkleroot: String
    public let tx: [String]
    public let time: Int
    public let mediantime: Int
    public let nonce: Int
    public let bits: String
    public let difficulty: Double
    public let chainwork: String
    public let nTx: Int
    public let previousblockhash: String?
    public let nextblockhash: String?
    
    enum CodingKeys: String, CodingKey {
        case hash, confirmations, size, strippedsize, weight, height, version, versionHex, merkleroot, tx, time, mediantime, nonce, bits, difficulty, chainwork, nTx, previousblockhash, nextblockhash
    }
}