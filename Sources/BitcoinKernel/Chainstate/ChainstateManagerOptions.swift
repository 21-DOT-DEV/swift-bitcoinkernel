//
//  ChainstateManagerOptions.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

internal import libbitcoinkernel

/// Builder for constructing a ``ChainstateManager`` — configures data paths,
/// worker-thread count, reindex behavior, and in-memory-database flags.
///
/// Instantiate with a context and a data directory, tune with the setters,
/// then pass to ``ChainstateManager/init(options:)``. On Apple platforms,
/// place the data directory inside Application Support with
/// `isExcludedFromBackup = true` — chainstate is reproducible from the
/// network and doesn't belong in iCloud backups.
///
/// Wraps the opaque `btck_ChainstateManagerOptions` type; `deinit` calls
/// `btck_chainstate_manager_options_destroy` when the last Swift reference
/// drops.
public final class ChainstateManagerOptions: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Creates chainstate manager options.
    ///
    /// - Parameters:
    ///   - context: The kernel context that the resulting manager will
    ///     validate against — its ``ChainParameters`` determines genesis
    ///     and consensus rules.
    ///   - dataDirectory: Absolute path to the data directory. Must be
    ///     writable; created if missing. Houses the block-index and
    ///     chainstate LevelDB databases.
    ///   - blocksDirectory: Absolute path for raw block files. Defaults to
    ///     `dataDirectory + "/blocks"`; override only when block storage
    ///     should live on a different filesystem (e.g. external drive).
    /// - Throws: ``KernelError/chainstateManagerOptionsCreationFailed`` if
    ///   the directory is inaccessible or on a filesystem the kernel does
    ///   not support.
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
    /// More threads help on CPU-bound signature verification during IBD.
    /// Bitcoin Core's `-par=N` convention: `0` means auto-detect (one per
    /// core, up to the kernel's internal cap of 15). Values outside `0...15`
    /// are clamped by the kernel.
    ///
    /// - Parameter count: Number of threads, `0` for auto-detect.
    public func setWorkerThreads(_ count: Int32) {
        btck_chainstate_manager_options_set_worker_threads_num(pointer, count)
    }

    /// Configures database wiping for reindex operations.
    ///
    /// Wiping forces the next ``ChainstateManager`` start to rebuild from
    /// scratch — useful for recovering from local DB corruption or for
    /// applying new validation flags to a previously-validated chain.
    /// Wiping only the chainstate DB (`chainstateDB: true, blockTreeDB: false`)
    /// is the equivalent of Bitcoin Core's `-reindex-chainstate`; wiping
    /// both is the equivalent of `-reindex`.
    ///
    /// - Parameters:
    ///   - blockTreeDB: Whether to wipe the block-index database.
    ///   - chainstateDB: Whether to wipe the chainstate (UTXO) database.
    /// - Returns: `true` if the configuration succeeded.
    @discardableResult
    public func setWipeDBs(blockTreeDB: Bool, chainstateDB: Bool) -> Bool {
        btck_chainstate_manager_options_set_wipe_dbs(
            pointer,
            blockTreeDB ? 1 : 0,
            chainstateDB ? 1 : 0
        ) == 0
    }

    /// Keeps the block-index database in RAM instead of on disk.
    ///
    /// Used by swift-bitcoin's test suite — see the regtest chainstate
    /// fixtures in `ChainstateManagerTests`. In production, leave disabled
    /// so the index survives process restart.
    ///
    /// - Parameter inMemory: `true` to use an in-memory block-index DB.
    public func setBlockTreeDBInMemory(_ inMemory: Bool) {
        btck_chainstate_manager_options_update_block_tree_db_in_memory(
            pointer, inMemory ? 1 : 0
        )
    }

    /// Keeps the chainstate (UTXO) database in RAM instead of on disk.
    ///
    /// Test-oriented; pairs with ``setBlockTreeDBInMemory(_:)`` to make a
    /// completely ephemeral chainstate that evaporates at process exit.
    /// Not suitable for production — the UTXO set must survive restart.
    ///
    /// - Parameter inMemory: `true` to use an in-memory chainstate DB.
    public func setChainstateDBInMemory(_ inMemory: Bool) {
        btck_chainstate_manager_options_update_chainstate_db_in_memory(
            pointer, inMemory ? 1 : 0
        )
    }

    deinit {
        btck_chainstate_manager_options_destroy(pointer)
    }
}
