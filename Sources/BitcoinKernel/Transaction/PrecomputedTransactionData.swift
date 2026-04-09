internal import libbitcoinkernel

/// Pre-computed data for efficient script verification.
///
/// For taproot verification, the spent outputs must be provided at creation.
/// For non-taproot verification, `spentOutputs` may be `nil`.
///
/// Wraps the opaque `btck_PrecomputedTransactionData` type. ARC via `deinit`
/// calls `btck_precomputed_transaction_data_destroy` when the last reference drops.
public final class PrecomputedTransactionData: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Creates precomputed data for script verification.
    ///
    /// - Parameters:
    ///   - transaction: The spending transaction.
    ///   - spentOutputs: The outputs being spent (required for taproot, optional otherwise).
    /// - Throws: ``KernelError/precomputedDataCreationFailed`` if the C API returns null.
    public init(transaction: Transaction, spentOutputs: [TransactionOutput]? = nil) throws {
        let txPtr = transaction.pointer

        if let spentOutputs {
            var ptrs: [OpaquePointer?] = spentOutputs.map { $0.pointer }
            guard let ptr = ptrs.withUnsafeMutableBufferPointer({ buf in
                btck_precomputed_transaction_data_create(
                    txPtr,
                    buf.baseAddress,
                    buf.count
                )
            }) else {
                throw KernelError.precomputedDataCreationFailed
            }
            self.pointer = ptr
        } else {
            guard let ptr = btck_precomputed_transaction_data_create(txPtr, nil, 0) else {
                throw KernelError.precomputedDataCreationFailed
            }
            self.pointer = ptr
        }
    }

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        btck_precomputed_transaction_data_destroy(pointer)
    }
}
