internal import libbitcoinkernel

/// An entry in the block tree (block index).
///
/// Wraps the unowned `btck_BlockTreeEntry` pointer. This is a **view type** —
/// its lifetime is tied to the ``ChainstateManager`` that owns it. No `deinit`
/// destruction is performed.
public final class BlockTreeEntry: @unchecked Sendable {
    let pointer: OpaquePointer
    /// Retains the owning manager so the C pointer stays valid.
    private let _owner: AnyObject?

    /// Internal initializer from an unowned C pointer.
    init(pointer: OpaquePointer, owner: AnyObject? = nil) {
        self.pointer = pointer
        self._owner = owner
    }

    /// The block height.
    public var height: Int32 {
        btck_block_tree_entry_get_height(pointer)
    }

    /// The block hash (unowned view — lifetime tied to this entry).
    public var blockHash: BlockHash {
        let viewPtr = btck_block_tree_entry_get_block_hash(pointer)
        return BlockHash(pointer: btck_block_hash_copy(viewPtr))
    }

    /// The block header (owned copy).
    public var blockHeader: BlockHeader {
        BlockHeader(pointer: btck_block_tree_entry_get_block_header(pointer))
    }

    /// The previous block tree entry, or `nil` for the genesis block.
    public var previous: BlockTreeEntry? {
        guard let ptr = btck_block_tree_entry_get_previous(pointer) else {
            return nil
        }
        return BlockTreeEntry(pointer: ptr, owner: _owner)
    }

    /// Whether this entry equals another.
    public func equals(_ other: BlockTreeEntry) -> Bool {
        btck_block_tree_entry_equals(pointer, other.pointer) != 0
    }
}
