/// Possible warning types issued by validation.
///
/// Maps to `btck_Warning` constants in the kernel C API.
public enum Warning: UInt8, Sendable {
    case unknownNewRulesActivated = 0
    case largeWorkInvalidChain    = 1
}
