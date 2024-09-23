import Foundation

public struct NodeAddress: Codable {
    public let time: Int64
    public let services: UInt64
    public let address: String
    public let port: Int
}