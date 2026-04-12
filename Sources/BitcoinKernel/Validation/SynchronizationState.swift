/// Current synchronization state passed to tip-changed callbacks.
///
/// Maps to `btck_SynchronizationState` constants in the kernel C API.
public enum SynchronizationState: UInt8, Sendable {
    /// Initial reindexing of blocks from disk.
    case initReindex  = 0
    /// Initial block download from the network.
    case initDownload = 1
    /// Normal operation after initial synchronization is complete.
    case postInit     = 2
}
