/// Categories for filtering kernel log messages.
///
/// Maps to `btck_LogCategory` constants in the kernel C API.
public enum LogCategory: UInt8, Sendable, CaseIterable, Codable {
    /// All categories. Enables or disables logging for every category at once.
    case all          = 0
    /// Benchmarking and timing measurements.
    case bench        = 1
    /// Block storage and disk I/O.
    case blockStorage = 2
    /// Coin database (UTXO set) operations.
    case coinDB       = 3
    /// LevelDB low-level operations.
    case levelDB      = 4
    /// Mempool transaction processing.
    case mempool      = 5
    /// Block pruning operations.
    case prune        = 6
    /// Random number generation.
    case rand         = 7
    /// Block reindexing.
    case reindex      = 8
    /// Block and transaction validation.
    case validation   = 9
    /// General kernel operations.
    case kernel       = 10
}
