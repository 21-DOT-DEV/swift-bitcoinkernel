internal import libbitcoinkernel
import Foundation

/// A Bitcoin transaction.
///
/// Wraps the opaque `btck_Transaction` type. ARC via `deinit` calls
/// `btck_transaction_destroy` when the last reference drops.
public final class Transaction: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Creates a transaction from serialized (consensus-encoded) data.
    ///
    /// - Parameter data: The raw transaction bytes.
    /// - Throws: ``KernelError/transactionCreationFailed`` if parsing fails.
    public init(_ data: Data) throws {
        guard let ptr = data.withUnsafeBytes({ rawBuf -> OpaquePointer? in
            guard let baseAddress = rawBuf.baseAddress else { return nil }
            return btck_transaction_create(baseAddress, rawBuf.count)
        }) else {
            throw KernelError.transactionCreationFailed
        }
        self.pointer = ptr
    }

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The number of outputs in this transaction.
    public var outputCount: Int {
        btck_transaction_count_outputs(pointer)
    }

    /// The number of inputs in this transaction.
    public var inputCount: Int {
        btck_transaction_count_inputs(pointer)
    }

    /// Returns the output at the given index (owned copy).
    ///
    /// - Parameter index: Zero-based output index.
    /// - Precondition: `index` must be in `0..<outputCount`.
    public func output(at index: Int) -> TransactionOutput {
        let viewPtr = btck_transaction_get_output_at(pointer, index)
        return TransactionOutput(pointer: btck_transaction_output_copy(viewPtr))
    }

    /// Returns the input at the given index (owned copy).
    ///
    /// - Parameter index: Zero-based input index.
    /// - Precondition: `index` must be in `0..<inputCount`.
    public func input(at index: Int) -> TransactionInput {
        let viewPtr = btck_transaction_get_input_at(pointer, index)
        return TransactionInput(pointer: btck_transaction_input_copy(viewPtr))
    }

    /// The transaction ID (owned copy).
    public var txid: Txid {
        let viewPtr = btck_transaction_get_txid(pointer)
        return Txid(pointer: btck_txid_copy(viewPtr))
    }

    /// The consensus-serialized transaction bytes.
    public var data: Data {
        guard let result = serializeToData({ writer, userData in
            btck_transaction_to_bytes(pointer, writer, userData)
        }) else {
            preconditionFailure("Serialization of a valid Transaction must not fail")
        }
        return result
    }

    deinit {
        btck_transaction_destroy(pointer)
    }
}
