/// Status codes returned by script verification.
///
/// Maps to `btck_ScriptVerifyStatus` constants in the kernel C API.
public enum ScriptVerifyStatus: UInt8, Sendable {
    case ok                          = 0
    case errorInvalidFlagsCombination = 1
    case errorSpentOutputsRequired   = 2
}
