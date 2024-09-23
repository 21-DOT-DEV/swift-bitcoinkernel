import Foundation

public struct MempoolEntry: Codable {
    public let vsize: Int
    public let weight: Int
    public let fee: Double
    public let modifiedfee: Double
    public let time: Int
    public let height: Int
    public let descendantcount: Int
    public let descendantsize: Int
    public let descendantfees: Double
    public let ancestorcount: Int
    public let ancestorsize: Int
    public let ancestorfees: Double
    public let wtxid: String
    public let fees: Fees
    public let depends: [String]
    public let spentby: [String]
    public let bip125Replaceable: Bool
    public let unbroadcast: Bool
    
    public struct Fees: Codable {
        public let base: Double
        public let modified: Double
        public let ancestor: Double
        public let descendant: Double
    }
    
    enum CodingKeys: String, CodingKey {
        case vsize, weight, fee, modifiedfee, time, height, descendantcount, descendantsize, descendantfees, ancestorcount, ancestorsize, ancestorfees, wtxid, fees, depends, spentby
        case bip125Replaceable = "bip125-replaceable"
        case unbroadcast
    }
}