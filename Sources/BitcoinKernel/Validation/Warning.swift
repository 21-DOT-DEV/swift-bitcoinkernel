/// Possible warning types issued by validation.
///
/// Maps to `btck_Warning` constants in the kernel C API.
public enum Warning: UInt8, Sendable, CaseIterable, Codable, CustomStringConvertible {
    /// Unknown new consensus rules may have been activated.
    case unknownNewRulesActivated = 0
    /// A large-work chain of invalid blocks has been detected.
    case largeWorkInvalidChain    = 1

    public var description: String {
        switch self {
        case .unknownNewRulesActivated: return "unknown new rules activated"
        case .largeWorkInvalidChain:    return "large-work invalid chain detected"
        }
    }
}
