/// Flags controlling script verification constraints.
///
/// Compose flags using set operations: `[.p2sh, .witness, .taproot]`.
/// Maps to `btck_ScriptVerificationFlags` constants in the kernel C API.
public struct ScriptVerificationFlags: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// No flags.
    public static let none                  = ScriptVerificationFlags([])
    /// Evaluate P2SH (BIP16) subscripts.
    public static let p2sh                  = ScriptVerificationFlags(rawValue: 1 << 0)
    /// Enforce strict DER (BIP66) compliance.
    public static let derSig                = ScriptVerificationFlags(rawValue: 1 << 2)
    /// Enforce NULLDUMMY (BIP147).
    public static let nullDummy             = ScriptVerificationFlags(rawValue: 1 << 4)
    /// Enable CHECKLOCKTIMEVERIFY (BIP65).
    public static let checkLockTimeVerify   = ScriptVerificationFlags(rawValue: 1 << 9)
    /// Enable CHECKSEQUENCEVERIFY (BIP112).
    public static let checkSequenceVerify   = ScriptVerificationFlags(rawValue: 1 << 10)
    /// Enable WITNESS (BIP141).
    public static let witness               = ScriptVerificationFlags(rawValue: 1 << 11)
    /// Enable TAPROOT (BIPs 341 & 342).
    public static let taproot               = ScriptVerificationFlags(rawValue: 1 << 17)
    /// All standard verification flags.
    public static let all: ScriptVerificationFlags = [
        .p2sh, .derSig, .nullDummy,
        .checkLockTimeVerify, .checkSequenceVerify,
        .witness, .taproot,
    ]
}
