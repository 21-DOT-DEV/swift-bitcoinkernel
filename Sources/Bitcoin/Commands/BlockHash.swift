import Foundation

public struct BlockHash: Codable {
    public let hash: String
    
    public init(hash: String) {
        self.hash = hash
    }
}