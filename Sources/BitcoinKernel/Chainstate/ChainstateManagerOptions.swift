internal import libbitcoinkernel

/// Options for creating a chainstate manager.
///
/// Wraps the opaque `btck_ChainstateManagerOptions` type. ARC via `deinit`
/// calls `btck_chainstate_manager_options_destroy` when the last reference drops.
public final class ChainstateManagerOptions: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Creates chainstate manager options.
    ///
    /// - Parameters:
    ///   - context: The kernel context.
    ///   - dataDirectory: Path to the data directory for blockchain storage.
    ///   - blocksDirectory: Path to the blocks directory. Defaults to `dataDirectory + "/blocks"`.
    /// - Throws: ``KernelError/chainstateManagerOptionsCreationFailed`` if creation fails.
    public init(context: Context, dataDirectory: String, blocksDirectory: String? = nil) throws {
        let blocksDir = blocksDirectory ?? (dataDirectory + "/blocks")
        guard let ptr = dataDirectory.withCString({ dataCStr in
            blocksDir.withCString { blocksCStr in
                btck_chainstate_manager_options_create(
                    context.pointer,
                    dataCStr, dataDirectory.utf8.count,
                    blocksCStr, blocksDir.utf8.count
                )
            }
        }) else {
            throw KernelError.chainstateManagerOptionsCreationFailed
        }
        self.pointer = ptr
    }

    /// Sets the number of worker threads for parallel script verification.
    ///
    /// - Parameter count: Number of threads (clamped to 0–15 internally).
    public func setWorkerThreads(_ count: Int32) {
        btck_chainstate_manager_options_set_worker_threads_num(pointer, count)
    }

    /// Configures database wiping for reindex operations.
    ///
    /// - Parameters:
    ///   - blockTreeDB: Whether to wipe the block tree database.
    ///   - chainstateDB: Whether to wipe the chainstate database.
    /// - Returns: `true` if the configuration succeeded.
    @discardableResult
    public func setWipeDBs(blockTreeDB: Bool, chainstateDB: Bool) -> Bool {
        btck_chainstate_manager_options_set_wipe_dbs(
            pointer,
            blockTreeDB ? 1 : 0,
            chainstateDB ? 1 : 0
        ) == 0
    }

    /// Sets whether the block tree database should be in memory.
    public func setBlockTreeDBInMemory(_ inMemory: Bool) {
        btck_chainstate_manager_options_update_block_tree_db_in_memory(
            pointer, inMemory ? 1 : 0
        )
    }

    /// Sets whether the chainstate database should be in memory.
    public func setChainstateDBInMemory(_ inMemory: Bool) {
        btck_chainstate_manager_options_update_chainstate_db_in_memory(
            pointer, inMemory ? 1 : 0
        )
    }

    deinit {
        btck_chainstate_manager_options_destroy(pointer)
    }
}
