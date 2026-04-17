/// The severity level for kernel log messages.
///
/// Maps to `btck_LogLevel` constants in the kernel C API.
public enum LogLevel: UInt8, Sendable, CaseIterable, Codable, Comparable {
    /// Most verbose level; logs everything including internal details.
    case trace = 0
    /// Detailed debugging information.
    case debug = 1
    /// General informational messages.
    case info  = 2

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
