internal import libbitcoinkernel

/// The spent outputs (``Coin`` values) for a single transaction — the
/// UTXOs that transaction's inputs consumed.
///
/// Carried inside a ``BlockSpentOutputs``; obtained via
/// ``BlockSpentOutputs/transactionSpentOutputs(at:)``. The index aligns
/// with the owning transaction's ``Transaction/input(at:)`` list: coin
/// `n` is what `input(at: n)` spent.
///
/// Wraps the opaque `btck_TransactionSpentOutputs` type; `deinit` calls
/// `btck_transaction_spent_outputs_destroy` when the last Swift reference
/// drops.
public final class TransactionSpentOutputs: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The number of coins (spent outputs) in this transaction — equals
    /// the owning transaction's ``Transaction/inputCount``.
    public var count: Int {
        btck_transaction_spent_outputs_count(pointer)
    }

    /// Returns the coin at the given index as an owned ``Coin`` (safe to
    /// store past this container's lifetime).
    ///
    /// - Parameter index: Zero-based index matching the transaction's
    ///   ``Transaction/input(at:)`` index.
    /// - Precondition: `index` must be in `0..<count`.
    public func coin(at index: Int) -> Coin {
        let viewPtr = btck_transaction_spent_outputs_get_coin_at(pointer, index)
        return Coin(pointer: btck_coin_copy(viewPtr))
    }

    deinit {
        btck_transaction_spent_outputs_destroy(pointer)
    }
}
