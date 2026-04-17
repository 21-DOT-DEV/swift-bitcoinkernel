/// Status codes returned by script verification.
///
/// Maps to `btck_ScriptVerifyStatus` constants in the kernel C API.
public enum ScriptVerifyStatus: UInt8, Sendable, CaseIterable, Codable, CustomStringConvertible {
    case ok                          = 0
    case errorInvalidFlagsCombination = 1
    case errorSpentOutputsRequired   = 2

    public var description: String {
        switch self {
        case .ok:                          return "ok"
        case .errorInvalidFlagsCombination: return "invalid flags combination"
        case .errorSpentOutputsRequired:   return "spent outputs required"
        }
    }
}
