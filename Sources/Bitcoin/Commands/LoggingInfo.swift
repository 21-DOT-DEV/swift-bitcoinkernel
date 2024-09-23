import Foundation

public struct LoggingInfo: Codable {
    public let categories: [String: Bool]
    
    public init(categories: [String: Bool]) {
        self.categories = categories
    }
}