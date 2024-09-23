import Foundation

public struct FundRawTransactionOptions: Codable {
    public let addInputs: Bool?
    public let changeAddress: String?
    public let changePosition: Int?
    public let changeType: String?
    public let includeWatching: Bool?
    public let lockUnspents: Bool?
    public let feeRate: Double?
    public let subtractFeeFromOutputs: [Int]?
    public let replaceable: Bool?
    public let confTarget: Int?
    public let estimateMode: String?
    
    enum CodingKeys: String, CodingKey {
        case addInputs = "add_inputs"
        case changeAddress, changePosition, changeType, includeWatching, lockUnspents, feeRate, subtractFeeFromOutputs, replaceable
        case confTarget = "conf_target"
        case estimateMode = "estimate_mode"
    }
}

public struct FundRawTransactionResult: Codable {
    public let hex: String
    public let fee: Double
    public let changepos: Int
}