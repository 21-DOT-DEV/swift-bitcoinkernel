internal import libbitcoinkernel

/// A transaction output (value + script pubkey).
///
/// Wraps the opaque `btck_TransactionOutput` type. ARC via `deinit` calls
/// `btck_transaction_output_destroy` when the last reference drops.
public final class TransactionOutput: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Creates a transaction output from a script pubkey and amount.
    ///
    /// - Parameters:
    ///   - scriptPubkey: The locking script for this output.
    ///   - amount: The value in satoshis.
    public init(scriptPubkey: ScriptPubkey, amount: Int64) {
        self.pointer = btck_transaction_output_create(scriptPubkey.pointer, amount)
    }

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The script pubkey of this output (owned copy).
    public var scriptPubkey: ScriptPubkey {
        let viewPtr = btck_transaction_output_get_script_pubkey(pointer)
        return ScriptPubkey(pointer: btck_script_pubkey_copy(viewPtr))
    }

    /// The output amount in satoshis.
    public var amount: Int64 {
        btck_transaction_output_get_amount(pointer)
    }

    deinit {
        btck_transaction_output_destroy(pointer)
    }
}
