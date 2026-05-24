/// Categories for filtering kernel log messages — pass to
/// ``enableLogCategory(_:)`` / ``disableLogCategory(_:)`` /
/// ``setLogLevel(category:level:)`` to control the noise level.
///
/// Categories map 1:1 onto Bitcoin Core's `BCLog::LogFlags` values.
/// Enabling a category routes matching log lines to any active
/// ``LoggingConnection``; disabling suppresses them at the source.
///
/// Maps to `btck_LogCategory` constants in the kernel C API.
public enum LogCategory: UInt8, Sendable, CaseIterable, Codable {
    /// All categories. Enabling or disabling this affects every other
    /// case at once — use ``enableLogCategory(_:)`` with `.all` to
    /// firehose all kernel output.
    case all          = 0

    /// Benchmarking and timing measurements — per-block validation
    /// timing, script cache hit rates, etc.
    case bench        = 1

    /// Block storage and disk I/O — `blk*.dat` and `rev*.dat` reads and
    /// writes, flushing, and file rotation.
    case blockStorage = 2

    /// Coin database (UTXO set) operations — cache fills, flushes, and
    /// warmup progress.
    case coinDB       = 3

    /// LevelDB low-level operations — the storage backend for the block
    /// index and chainstate.
    case levelDB      = 4

    /// Mempool transaction processing — swift-bitcoinkernel's kernel does not
    /// run a mempool, so this category is effectively quiet.
    case mempool      = 5

    /// Block pruning operations — mainnet-only; swift-bitcoinkernel does not
    /// currently expose `-prune=N`, so this category is effectively quiet.
    case prune        = 6

    /// Random number generation — entropy sources, RNG state.
    case rand         = 7

    /// Block reindexing — triggered by
    /// ``ChainstateManagerOptions/setWipeDBs(blockTreeDB:chainstateDB:)``.
    case reindex      = 8

    /// Block and transaction validation — the highest-signal category
    /// for debugging rejected blocks or unexpected reorgs.
    case validation   = 9

    /// General kernel operations — initialization, shutdown, and
    /// anything not covered by a more specific category.
    case kernel       = 10
}
