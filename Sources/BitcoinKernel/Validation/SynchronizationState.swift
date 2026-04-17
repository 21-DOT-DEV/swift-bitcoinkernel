/// Current synchronization state passed to tip-changed callbacks.
///
/// Maps to `btck_SynchronizationState` constants in the kernel C API.
public enum SynchronizationState: UInt8, Sendable, CaseIterable, Codable, CustomStringConvertible {
    /// Initial reindexing of blocks from disk.
    case initReindex  = 0
    /// Initial block download from the network.
    case initDownload = 1
    /// Normal operation after initial synchronization is complete.
    case postInit     = 2

    public var description: String {
        switch self {
        case .initReindex:  return "reindexing"
        case .initDownload: return "downloading"
        case .postInit:     return "synchronized"
        }
    }
}
