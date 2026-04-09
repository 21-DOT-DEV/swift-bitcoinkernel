internal import libbitcoinkernel

/// A reference to a specific output of a previous transaction.
///
/// Transaction outpoints are obtained from a `TransactionInput` — there is
/// no public `create` initializer. The C API provides `copy` for ownership.
///
/// Wraps the opaque `btck_TransactionOutPoint` type. ARC via `deinit` calls
/// `btck_transaction_out_point_destroy` when the last reference drops.
public final class TransactionOutPoint: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The index of the output in the referenced transaction.
    public var index: UInt32 {
        btck_transaction_out_point_get_index(pointer)
    }

    /// The txid of the referenced transaction (owned copy).
    public var txid: Txid {
        let viewPtr = btck_transaction_out_point_get_txid(pointer)
        return Txid(pointer: btck_txid_copy(viewPtr))
    }

    deinit {
        btck_transaction_out_point_destroy(pointer)
    }
}
