import Foundation

public struct MempoolInfo: Codable {
    public let loaded: Bool
    public let size: Int
    public let bytes: Int
    public let usage: Int
    public let maxmempool: Int
    public let mempoolminfee: Double
    public let minrelaytxfee: Double
    public let unbroadcastcount: Int
    
    public init(loaded: Bool, size: Int, bytes: Int, usage: Int, maxmempool: Int, mempoolminfee: Double, minrelaytxfee: Double, unbroadcastcount: Int) {
        self.loaded = loaded
        self.size = size
        self.bytes = bytes
        self.usage = usage
        self.maxmempool = maxmempool
        self.mempoolminfee = mempoolminfee
        self.minrelaytxfee = minrelaytxfee
        self.unbroadcastcount = unbroadcastcount
    }
}