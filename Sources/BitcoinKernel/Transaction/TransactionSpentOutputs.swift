internal import libbitcoinkernel

/// The spent outputs (coins) for a single transaction.
///
/// Wraps the opaque `btck_TransactionSpentOutputs` type. ARC via `deinit` calls
/// `btck_transaction_spent_outputs_destroy` when the last reference drops.
public final class TransactionSpentOutputs: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The number of coins (spent outputs) in this transaction.
    public var count: Int {
        btck_transaction_spent_outputs_count(pointer)
    }

    /// Returns the coin at the given index (owned copy).
    ///
    /// - Parameter index: Zero-based index.
    /// - Precondition: `index` must be in `0..<count`.
    public func coin(at index: Int) -> Coin {
        let viewPtr = btck_transaction_spent_outputs_get_coin_at(pointer, index)
        return Coin(pointer: btck_coin_copy(viewPtr))
    }

    deinit {
        btck_transaction_spent_outputs_destroy(pointer)
    }
}
