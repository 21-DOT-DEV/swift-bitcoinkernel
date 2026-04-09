internal import libbitcoinkernel

/// Manages chainstate for block validation and chain queries.
///
/// Wraps the opaque `btck_ChainstateManager` type. ARC via `deinit` calls
/// `btck_chainstate_manager_destroy` when the last reference drops.
public final class ChainstateManager: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Creates a chainstate manager from options.
    ///
    /// - Parameter options: The chainstate manager options.
    /// - Throws: ``KernelError/chainstateManagerCreationFailed`` if creation fails.
    public init(options: ChainstateManagerOptions) throws {
        guard let ptr = btck_chainstate_manager_create(options.pointer) else {
            throw KernelError.chainstateManagerCreationFailed
        }
        self.pointer = ptr
    }

    /// The best (tip) block tree entry (view — retains this manager).
    public var bestEntry: BlockTreeEntry {
        BlockTreeEntry(pointer: btck_chainstate_manager_get_best_entry(pointer), owner: self)
    }

    /// The active chain (view — retains this manager).
    public var activeChain: Chain {
        Chain(pointer: btck_chainstate_manager_get_active_chain(pointer), owner: self)
    }

    /// Looks up a block tree entry by its block hash.
    ///
    /// - Parameter hash: The block hash to look up.
    /// - Returns: The block tree entry, or `nil` if not found.
    public func blockTreeEntry(byHash hash: BlockHash) -> BlockTreeEntry? {
        guard let ptr = btck_chainstate_manager_get_block_tree_entry_by_hash(
            pointer, hash.pointer
        ) else {
            return nil
        }
        return BlockTreeEntry(pointer: ptr, owner: self)
    }

    /// Processes a block header for validation.
    ///
    /// - Parameters:
    ///   - header: The block header to process.
    ///   - state: The validation state (populated on return).
    /// - Returns: `true` if header processing completed successfully.
    @discardableResult
    public func processBlockHeader(_ header: BlockHeader, state: BlockValidationState) -> Bool {
        btck_chainstate_manager_process_block_header(
            pointer, header.pointer, state.pointer
        ) == 0
    }

    /// Processes a block for validation and potential inclusion in the chain.
    ///
    /// - Parameter block: The block to process.
    /// - Returns: A tuple of `(success, isNew)` where `success` indicates processing
    ///   completed and `isNew` indicates whether this was a new block.
    public func processBlock(_ block: Block) -> (success: Bool, isNew: Bool) {
        var newBlock: Int32 = 0
        let result = btck_chainstate_manager_process_block(
            pointer, block.pointer, &newBlock
        )
        return (result == 0, newBlock != 0)
    }

    /// Reads a block from disk by its block tree entry.
    ///
    /// - Parameter entry: The block tree entry pointing to the block on disk.
    /// - Returns: The block, or `nil` on read failure.
    public func readBlock(at entry: BlockTreeEntry) -> Block? {
        guard let ptr = btck_block_read(pointer, entry.pointer) else {
            return nil
        }
        return Block(pointer: ptr)
    }

    /// Reads the spent outputs for a block from disk.
    ///
    /// - Parameter entry: The block tree entry pointing to the block on disk.
    /// - Returns: The block's spent outputs, or `nil` on read failure.
    public func readBlockSpentOutputs(at entry: BlockTreeEntry) -> BlockSpentOutputs? {
        guard let ptr = btck_block_spent_outputs_read(pointer, entry.pointer) else {
            return nil
        }
        return BlockSpentOutputs(pointer: ptr)
    }

    /// Imports blocks from block files.
    ///
    /// - Parameter filePaths: Paths to block files (e.g., `blk00000.dat`).
    /// - Returns: `true` if import completed successfully.
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
