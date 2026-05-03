internal import libbitcoinkernel

/// The chainstate manager — validates blocks, maintains the block index
/// and UTXO set, and exposes the active chain.
///
/// One chainstate manager per on-disk data directory. Instantiate from a
/// ``ChainstateManagerOptions`` (which binds it to a ``Context``), then
/// feed blocks via ``processBlock(_:)`` or headers via
/// ``processBlockHeader(_:state:)``. ``BlockchainSync`` drives the
/// block-feeding loop automatically; direct callers typically only use
/// ``processBlock(_:)`` for replay or testing.
///
/// Wraps the opaque `btck_ChainstateManager` type; `deinit` calls
/// `btck_chainstate_manager_destroy` when the last Swift reference drops.
public final class ChainstateManager: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Creates a chainstate manager from options.
    ///
    /// Opens (or creates) the block-index and chainstate LevelDB databases
    /// in the paths configured on `options`. On a fresh data directory this
    /// initializes them with the genesis block for the configured
    /// ``ChainType``; on an existing directory it loads the state left
    /// behind by the previous run.
    ///
    /// - Parameter options: Preconfigured options — including context, data
    ///   directory, worker-thread count, and in-memory-DB flags.
    /// - Throws: ``KernelError/chainstateManagerCreationFailed`` if opening
    ///   the databases fails. Common causes are documented on the error case.
    public init(options: ChainstateManagerOptions) throws {
        guard let ptr = btck_chainstate_manager_create(options.pointer) else {
            throw KernelError.chainstateManagerCreationFailed
        }
        self.pointer = ptr
    }

    /// The best (tip) block tree entry — the block with the most cumulative
    /// proof-of-work that the kernel currently considers the chain's head.
    ///
    /// A **view type** whose lifetime is tied to this manager; keep the
    /// manager alive while you hold the returned ``BlockTreeEntry``, or
    /// promote to an owned ``BlockTreeEntrySnapshot`` for safe storage.
    /// Reads ``bestEntry`` repeatedly during a sync run to track progress.
    public var bestEntry: BlockTreeEntry {
        BlockTreeEntry(pointer: btck_chainstate_manager_get_best_entry(pointer), owner: self)
    }

    /// The active chain — the sequence of blocks from genesis to
    /// ``bestEntry``, navigable by height.
    ///
    /// A **view type** backed by the manager; see ``Chain`` for the
    /// operations it exposes. Use ``Chain/entry(atHeight:)`` for height
    /// lookups and ``Chain/contains(_:)`` to test whether a specific
    /// ``BlockTreeEntry`` is on the active chain (versus a side chain).
    public var activeChain: Chain {
        Chain(pointer: btck_chainstate_manager_get_active_chain(pointer), owner: self)
    }

    /// Looks up a block tree entry by its block hash.
    ///
    /// Searches the full block index — which includes blocks on side chains
    /// the kernel has evaluated but not adopted, not just the active chain.
    /// Cheap: backed by an in-memory hash table.
    ///
    /// - Parameter hash: The block hash to look up.
    /// - Returns: The matching ``BlockTreeEntry``, or `nil` if the kernel
    ///   has no record of a block with that hash.
    public func blockTreeEntry(byHash hash: BlockHash) -> BlockTreeEntry? {
        guard let ptr = btck_chainstate_manager_get_block_tree_entry_by_hash(
            pointer, hash.pointer
        ) else {
            return nil
        }
        return BlockTreeEntry(pointer: ptr, owner: self)
    }

    /// Processes a block header for validation — runs Bitcoin Core's
    /// [`AcceptBlockHeader`](https://github.com/bitcoin/bitcoin/blob/master/src/validation.cpp)
    /// checks without requiring the full block body.
    ///
    /// Useful for header-first IBD patterns where headers arrive before
    /// blocks. A `true` return means the header passed initial checks
    /// (proof-of-work, timestamp bounds, version-bit activation, linkage
    /// to a known parent) — not that the block extends the best chain.
    /// Inspect `state` for a typed rejection reason on failure.
    ///
    /// - Parameters:
    ///   - header: The block header to process.
    ///   - state: Populated on return with the validation result.
    /// - Returns: `true` if header processing completed successfully.
    @discardableResult
    public func processBlockHeader(_ header: BlockHeader, state: BlockValidationState) -> Bool {
        btck_chainstate_manager_process_block_header(
            pointer, header.pointer, state.pointer
        ) == 0
    }

    /// Processes a block for validation and potential inclusion in the
    /// active chain — the workhorse of every sync run.
    ///
    /// Runs `CheckBlock` + `ContextualCheckBlock` + `ConnectBlock` from
    /// Bitcoin Core's [`validation.cpp`](https://github.com/bitcoin/bitcoin/blob/master/src/validation.cpp).
    /// On success, the chainstate advances; on a chain-reorg scenario the
    /// kernel may internally switch to a new best chain without any extra
    /// caller action. This call can take seconds on mainnet-sized blocks
    /// and is interruptible via ``Context/interrupt()``.
    ///
    /// - Parameter block: The block to process.
    /// - Returns: A tuple of `(success, isNew)`. `success` is `true` if the
    ///   kernel accepted the block OR already had it; inspect the post-call
    ///   ``bestEntry`` to see whether this block became the new tip. `isNew`
    ///   is `true` if the kernel had not previously seen this block.
    public func processBlock(_ block: Block) -> (success: Bool, isNew: Bool) {
        var newBlock: Int32 = 0
        let result = btck_chainstate_manager_process_block(
            pointer, block.pointer, &newBlock
        )
        return (result == 0, newBlock != 0)
    }

    /// Reads a previously-processed block from disk by its block tree entry.
    ///
    /// Returns `nil` when the block index lists the entry but the block
    /// body is not on disk — e.g., an in-memory chainstate, a pruned data
    /// directory, or an entry from a side chain that was never fully
    /// validated.
    ///
    /// - Parameter entry: The block tree entry pointing to the block.
    /// - Returns: The block, or `nil` on read failure.
    public func readBlock(at entry: BlockTreeEntry) -> Block? {
        guard let ptr = btck_block_read(pointer, entry.pointer) else {
            return nil
        }
        return Block(pointer: ptr)
    }

    /// Reads the spent outputs (undo data) for a block from disk — the
    /// collection of UTXOs that this block consumed.
    ///
    /// Spent-output data is what lets the kernel undo a block during a
    /// reorg. Returns `nil` for the genesis block (no inputs spent, no
    /// undo data written) and when the undo file is not present on disk.
    ///
    /// - Parameter entry: The block tree entry pointing to the block.
    /// - Returns: The block's spent outputs, or `nil` on read failure.
    public func readBlockSpentOutputs(at entry: BlockTreeEntry) -> BlockSpentOutputs? {
        guard let ptr = btck_block_spent_outputs_read(pointer, entry.pointer) else {
            return nil
        }
        return BlockSpentOutputs(pointer: ptr)
    }

    /// Imports blocks from on-disk block files (`blk00000.dat`-style).
    ///
    /// Replays raw block files into the chainstate — typically used after
    /// copying a block directory from another node to avoid re-downloading
    /// historical blocks. This is a long-running operation; cancel via
    /// ``Context/interrupt()``.
    ///
    /// - Parameter filePaths: Absolute paths to block files. Empty list is
    ///   a no-op that returns `true`.
    /// - Returns: `true` if import completed successfully (or there was
    ///   nothing to do); `false` if any file failed to import.
    @discardableResult
    public func importBlocks(from filePaths: [String]) -> Bool {
        guard !filePaths.isEmpty else { return true }

        return withCStringPointers(filePaths[...], accumulated: []) { ptrs in
            var pointers: [UnsafePointer<CChar>?] = ptrs
            var lengths = filePaths.map { $0.utf8.count }
            return pointers.withUnsafeMutableBufferPointer { ptrsBuf in
                lengths.withUnsafeMutableBufferPointer { lensBuf in
                    guard let ptrsBase = ptrsBuf.baseAddress,
                          let lensBase = lensBuf.baseAddress else { return false }
                    return btck_chainstate_manager_import_blocks(
                        pointer,
                        ptrsBase, lensBase,
                        filePaths.count
                    ) == 0
                }
            }
        }
    }

    /// Recursively nests `withCString` calls so all C string pointers remain
    /// valid simultaneously when `body` is finally invoked.
    private func withCStringPointers(
        _ strings: ArraySlice<String>,
        accumulated: [UnsafePointer<CChar>],
        body: ([UnsafePointer<CChar>]) -> Bool
    ) -> Bool {
        guard let first = strings.first else { return body(accumulated) }
        return first.withCString { cStr in
            withCStringPointers(strings.dropFirst(), accumulated: accumulated + [cStr], body: body)
        }
    }

    deinit {
        btck_chainstate_manager_destroy(pointer)
    }
}
