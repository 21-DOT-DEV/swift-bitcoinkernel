internal import libbitcoinkernel

/// The spent-output (undo) data for every transaction in a block — the
/// collection of UTXOs that this block's transactions consumed.
///
/// Spent outputs are what the kernel writes to `rev*.dat` files alongside
/// `blk*.dat` so it can undo a block during a chain reorganization. Obtain
/// via ``ChainstateManager/readBlockSpentOutputs(at:)``; genesis blocks
/// have no undo data and the read returns `nil` there.
///
/// The index aligns with the block's transaction list, except that the
/// coinbase (always index 0 in the block) contributes no spent outputs.
///
/// Wraps the opaque `btck_BlockSpentOutputs` type; `deinit` calls
/// `btck_block_spent_outputs_destroy` when the last Swift reference drops.
public final class BlockSpentOutputs: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The number of transactions in this block whose inputs are recorded
    /// here — equals the block's non-coinbase transaction count.
    public var count: Int {
        btck_block_spent_outputs_count(pointer)
    }

    /// Returns the spent outputs for the transaction at the given index as
    /// an owned ``TransactionSpentOutputs`` (safe to store past this
    /// block's lifetime).
    ///
    /// - Parameter index: Zero-based index into the undo data. Index `0`
    ///   corresponds to the block's first **non-coinbase** transaction
    ///   (block transaction index 1).
    /// - Precondition: `index` must be in `0..<count`.
    public func transactionSpentOutputs(at index: Int) -> TransactionSpentOutputs {
        let viewPtr = btck_block_spent_outputs_get_transaction_spent_outputs_at(pointer, index)
        return TransactionSpentOutputs(pointer: btck_transaction_spent_outputs_copy(viewPtr))
    }

    deinit {
        btck_block_spent_outputs_destroy(pointer)
    }
}
