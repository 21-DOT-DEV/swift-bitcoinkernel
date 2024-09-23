import Foundation

public struct ChainTip: Codable {
    public let height: Int
    public let hash: String
    public let branchlen: Int
    public let status: String
    
    public init(height: Int, hash: String, branchlen: Int, status: String) {
        self.height = height
        self.hash = hash
        self.branchlen = branchlen
        self.status = status
    }
}