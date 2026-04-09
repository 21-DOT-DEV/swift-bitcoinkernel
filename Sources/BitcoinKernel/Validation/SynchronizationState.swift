/// Current synchronization state passed to tip-changed callbacks.
///
/// Maps to `btck_SynchronizationState` constants in the kernel C API.
public enum SynchronizationState: UInt8, Sendable {
    case initReindex  = 0
    case initDownload = 1
    case postInit     = 2
}
