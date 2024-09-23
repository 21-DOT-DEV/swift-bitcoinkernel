import Foundation

public struct PreviousTransaction: Codable {
    public let txid: String
    public let vout: Int
    public let scriptPubKey: String
    public let redeemScript: String?
    public let witnessScript: String?
    public let amount: Double?
}

public struct SignRawTransactionWithKeyError: Codable {
    public let txid: String
    public let vout: Int
    public let scriptSig: String
    public let sequence: Int
    public let error: String
}

public struct SignRawTransactionWithKeyResult: Codable {
    public let hex: String
    public let complete: Bool
    public let errors: [SignRawTransactionWithKeyError]?
}