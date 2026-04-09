internal import libbitcoinkernel

/// A view of the active blockchain.
///
/// Wraps the unowned `btck_Chain` pointer. This is a **view type** — its
/// lifetime is tied to the ``ChainstateManager`` that owns it. No `deinit`
/// destruction is performed.
public final class Chain: @unchecked Sendable {
    let pointer: OpaquePointer
    /// Retains the owning manager so the C pointer stays valid.
    private let _owner: AnyObject?

    /// Internal initializer from an unowned C pointer.
    init(pointer: OpaquePointer, owner: AnyObject? = nil) {
        self.pointer = pointer
        self._owner = owner
    }

    /// The height of the tip of the chain.
    public var height: Int32 {
        btck_chain_get_height(pointer)
    }

    /// Retrieves a block tree entry by its height in the active chain.
    ///
    /// - Parameter height: The block height.
    /// - Returns: The block tree entry at the given height, or `nil` if out of bounds.
    public func entry(atHeight height: Int32) -> BlockTreeEntry? {
        guard let ptr = btck_chain_get_by_height(pointer, height) else {
            return nil
        }
        return BlockTreeEntry(pointer: ptr, owner: _owner)
    }

    /// Whether the chain contains the given block tree entry.
    public func contains(_ entry: BlockTreeEntry) -> Bool {
        btck_chain_contains(pointer, entry.pointer) != 0
    }
}
