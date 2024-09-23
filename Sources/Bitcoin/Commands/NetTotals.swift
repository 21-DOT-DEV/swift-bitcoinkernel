import Foundation

public struct NetTotals: Codable {
    public struct UploadTarget: Codable {
        public let timeframe: Int
        public let target: Int
        public let targetReached: Bool
        public let serveHistoricalBlocks: Bool
        public let bytesLeftInCycle: Int
        public let timeLeftInCycle: Int
        
        enum CodingKeys: String, CodingKey {
            case timeframe, target
            case targetReached = "target_reached"
            case serveHistoricalBlocks = "serve_historical_blocks"
            case bytesLeftInCycle = "bytes_left_in_cycle"
            case timeLeftInCycle = "time_left_in_cycle"
        }
    }
    
    public let totalBytesRecv: Int
    public let totalBytesSent: Int
    public let timeMillis: Int
    public let uploadTarget: UploadTarget
    
    enum CodingKeys: String, CodingKey {
        case totalBytesRecv = "totalbytesrecv"
        case totalBytesSent = "totalbytessent"
        case timeMillis = "timemillis"
        case uploadTarget = "uploadtarget"
    }
}