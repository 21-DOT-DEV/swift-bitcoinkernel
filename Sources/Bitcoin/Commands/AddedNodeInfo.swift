import Foundation

public struct AddedNodeInfo: Codable {
    public struct Address: Codable {
        public let address: String
        public let connected: String
    }
    
    public let addednode: String
    public let connected: Bool
    public let addresses: [Address]?
}