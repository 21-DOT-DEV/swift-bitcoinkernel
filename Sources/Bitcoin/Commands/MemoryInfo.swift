import Foundation

public struct MemoryInfo: Codable {
    public let locked: LockedMemory
    
    public struct LockedMemory: Codable {
        public let used: Int
        public let free: Int
        public let total: Int
        public let locked: Int
        public let chunks_used: Int
        public let chunks_free: Int
    }
}

public struct MallocInfo: Codable {
    public let info: String
}