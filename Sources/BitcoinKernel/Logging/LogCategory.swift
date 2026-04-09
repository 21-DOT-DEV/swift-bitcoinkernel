/// Categories for filtering kernel log messages.
///
/// Maps to `btck_LogCategory` constants in the kernel C API.
public enum LogCategory: UInt8, Sendable {
    case all          = 0
    case bench        = 1
    case blockStorage = 2
    case coinDB       = 3
    case levelDB      = 4
    case mempool      = 5
    case prune        = 6
    case rand         = 7
    case reindex      = 8
    case validation   = 9
    case kernel       = 10
}
