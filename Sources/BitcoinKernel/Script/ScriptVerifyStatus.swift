/// Status codes returned alongside the `valid` boolean from
/// ``ScriptPubkey/verify(amount:transaction:precomputedData:inputIndex:flags:)``.
///
/// Distinguishes **usage errors** (bad flag combinations, missing spent
/// outputs) from **script-execution failures**. A return of
/// `(valid: false, status: .ok)` means the script evaluated cleanly but
/// the spend didn't satisfy its locking conditions — a genuine
/// verification failure. A non-`.ok` status means the verification
/// request itself was malformed.
///
/// Maps to `btck_ScriptVerifyStatus` constants in the kernel C API.
public enum ScriptVerifyStatus: UInt8, Sendable, CaseIterable, Codable, CustomStringConvertible {
    /// Verification completed without a usage error. The accompanying
    /// `valid` boolean decides whether the script actually succeeded.
    case ok                          = 0

    /// The flag set passed to `verify` is not internally consistent —
    /// e.g., ``ScriptVerificationFlags/taproot`` was set without
    /// ``ScriptVerificationFlags/witness``. Fix the caller; the
    /// verification did not run.
    case errorInvalidFlagsCombination = 1

    /// Taproot or witness verification was requested but the
    /// ``PrecomputedTransactionData`` argument lacked spent-outputs data.
    /// Reconstruct the precomputed data with the spent outputs and retry.
    case errorSpentOutputsRequired   = 2

    /// A short lowercase label suitable for error messages.
    public var description: String {
        switch self {
        case .ok:                          return "ok"
        case .errorInvalidFlagsCombination: return "invalid flags combination"
        case .errorSpentOutputsRequired:   return "spent outputs required"
        }
    }
}
