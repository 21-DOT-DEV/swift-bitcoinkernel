import Foundation

public struct MiningInfo: Codable {
    public let blocks: Int
    public let currentblockweight: Int?
    public let currentblocktx: Int?
    public let difficulty: Double
    public let networkhashps: Double
    public let pooledtx: Int
    public let chain: String
    public let warnings: String
    
    public init(blocks: Int, currentblockweight: Int?, currentblocktx: Int?, difficulty: Double, networkhashps: Double, pooledtx: Int, chain: String, warnings: String) {
        self.blocks = blocks
        self.currentblockweight = currentblockweight
        self.currentblocktx = currentblocktx
        self.difficulty = difficulty
        self.networkhashps = networkhashps
        self.pooledtx = pooledtx
        self.chain = chain
        self.warnings = warnings
    }
}