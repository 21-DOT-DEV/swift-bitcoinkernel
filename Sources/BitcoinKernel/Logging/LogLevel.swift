/// The severity level for kernel log messages.
///
/// Maps to `btck_LogLevel` constants in the kernel C API.
public enum LogLevel: UInt8, Sendable {
    case trace = 0
    case debug = 1
    case info  = 2
}
