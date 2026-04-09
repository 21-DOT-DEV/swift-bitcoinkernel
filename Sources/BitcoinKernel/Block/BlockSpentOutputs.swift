internal import libbitcoinkernel

/// The spent outputs for all transactions in a block.
///
/// Wraps the opaque `btck_BlockSpentOutputs` type. ARC via `deinit` calls
/// `btck_block_spent_outputs_destroy` when the last reference drops.
public final class BlockSpentOutputs: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The number of transaction spent outputs in this block.
    public var count: Int {
        btck_block_spent_outputs_count(pointer)
    }

    /// Returns the transaction spent outputs at the given index (unowned view).
    ///
    /// - Parameter index: Zero-based index.
    /// - Precondition: `index` must be in `0..<count`.
    public func transactionSpentOutputs(at index: Int) -> TransactionSpentOutputs {
        let viewPtr = btck_block_spent_outputs_get_transaction_spent_outputs_at(pointer, index)
        return TransactionSpentOutputs(pointer: btck_transaction_spent_outputs_copy(viewPtr))
    }

    deinit {
        btck_block_spent_outputs_destroy(pointer)
    }
}
