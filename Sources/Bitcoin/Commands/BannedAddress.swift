import Foundation

public struct BannedAddress: Codable {
    public let address: String
    public let bannedUntil: Int64
    public let banCreated: Int64
    
    enum CodingKeys: String, CodingKey {
        case address
        case bannedUntil = "banned_until"
        case banCreated = "ban_created"
    }
}