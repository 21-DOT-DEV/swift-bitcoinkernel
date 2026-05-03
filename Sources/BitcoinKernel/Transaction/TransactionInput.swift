internal import libbitcoinkernel

/// A transaction input — a reference to a previous output
/// (``TransactionOutPoint``) plus the scriptSig and witness data that
/// unlock it.
///
/// Inputs are obtained from a ``Transaction`` via
/// ``Transaction/input(at:)``; there is no public `create` initializer
/// because inputs are only meaningful in the context of a signed
/// transaction.
///
/// Wraps the opaque `btck_TransactionInput` type; `deinit` calls
/// `btck_transaction_input_destroy` when the last Swift reference drops.
public final class TransactionInput: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The outpoint this input spends — the (txid, output-index) pair
    /// identifying the previous output being consumed. For coinbase
    /// inputs, the outpoint's txid is all zeros and `index` is `0xFFFFFFFF`.
    /// Returns an owned copy that outlives this input.
    public var outPoint: TransactionOutPoint {
        let viewPtr = btck_transaction_input_get_out_point(pointer)
        return TransactionOutPoint(pointer: btck_transaction_out_point_copy(viewPtr))
    }

    deinit {
        btck_transaction_input_destroy(pointer)
    }
}
