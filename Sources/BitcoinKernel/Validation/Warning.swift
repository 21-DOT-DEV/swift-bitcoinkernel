/// Possible warning types issued by validation.
///
/// Maps to `btck_Warning` constants in the kernel C API.
public enum Warning: UInt8, Sendable {
    /// Unknown new consensus rules may have been activated.
    case unknownNewRulesActivated = 0
    /// A large-work chain of invalid blocks has been detected.
    case largeWorkInvalidChain    = 1
}
