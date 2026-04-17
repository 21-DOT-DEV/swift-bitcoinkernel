/// Whether a validated data structure is valid, invalid, or encountered an error.
///
/// Maps to `btck_ValidationMode` constants in the kernel C API.
public enum ValidationMode: UInt8, Sendable, CaseIterable, Codable, CustomStringConvertible {
    case valid         = 0
    case invalid       = 1
    case internalError = 2

    public var description: String {
        switch self {
        case .valid:         return "valid"
        case .invalid:       return "invalid"
        case .internalError: return "internal error"
        }
    }
}
