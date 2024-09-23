import Foundation

public struct BlockFilter: Codable {
    public let filter: String
    public let header: String
    
    public init(filter: String, header: String) {
        self.filter = filter
        self.header = header
    }
}