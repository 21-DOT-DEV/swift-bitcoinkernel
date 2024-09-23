import Foundation

public struct FinalizedPSBT: Codable {
    public let psbt: String?
    public let hex: String?
    public let complete: Bool
    
    public init(psbt: String?, hex: String?, complete: Bool) {
        self.psbt = psbt
        self.hex = hex
        self.complete = complete
    }
}