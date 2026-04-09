internal import libbitcoinkernel

/// A UTXO coin (unspent transaction output with metadata).
///
/// Wraps the opaque `btck_Coin` type. ARC via `deinit` calls
/// `btck_coin_destroy` when the last reference drops.
public final class Coin: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The block height at which the transaction creating this coin was included.
    public var confirmationHeight: UInt32 {
        btck_coin_confirmation_height(pointer)
    }

    /// Whether the containing transaction was a coinbase transaction.
    public var isCoinbase: Bool {
        btck_coin_is_coinbase(pointer) != 0
    }

    /// The transaction output of this coin (owned copy).
    public var output: TransactionOutput {
        let viewPtr = btck_coin_get_output(pointer)
        return TransactionOutput(pointer: btck_transaction_output_copy(viewPtr))
    }

    deinit {
        btck_coin_destroy(pointer)
    }
}
