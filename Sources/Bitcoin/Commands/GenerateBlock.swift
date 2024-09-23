import Foundation

public struct GenerateBlockResult: Codable {
    public let hash: String
    
    public init(hash: String) {
        self.hash = hash
    }
}