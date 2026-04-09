internal import libbitcoinkernel

/// A transaction input (reference to a previous output + unlock script).
///
/// Transaction inputs are only obtained from a `Transaction` — there is no
/// public `create` initializer. The C API provides `copy` for ownership.
///
/// Wraps the opaque `btck_TransactionInput` type. ARC via `deinit` calls
/// `btck_transaction_input_destroy` when the last reference drops.
public final class TransactionInput: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The outpoint this input spends (owned copy).
    public var outPoint: TransactionOutPoint {
        let viewPtr = btck_transaction_input_get_out_point(pointer)
        return TransactionOutPoint(pointer: btck_transaction_out_point_copy(viewPtr))
    }

    deinit {
        btck_transaction_input_destroy(pointer)
    }
}
