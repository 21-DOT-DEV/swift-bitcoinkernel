internal import libbitcoinkernel
import Foundation

/// A Bitcoin block (header + transactions).
///
/// Wraps the opaque `btck_Block` type. ARC via `deinit` calls
/// `btck_block_destroy` when the last reference drops.
public final class Block: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Creates a block from serialized (consensus-encoded) data.
    ///
    /// - Parameter data: The raw block bytes.
    /// - Throws: ``KernelError/blockCreationFailed`` if parsing fails.
    public init(_ data: Data) throws {
        guard let ptr = data.withUnsafeBytes({ rawBuf -> OpaquePointer? in
            guard let baseAddress = rawBuf.baseAddress else { return nil }
            return btck_block_create(baseAddress, rawBuf.count)
        }) else {
            throw KernelError.blockCreationFailed
        }
        self.pointer = ptr
    }

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The number of transactions in this block.
    public var transactionCount: Int {
        btck_block_count_transactions(pointer)
    }

    /// Returns the transaction at the given index (owned copy).
    ///
    /// - Parameter index: Zero-based transaction index.
    /// - Precondition: `index` must be in `0..<transactionCount`.
    public func transaction(at index: Int) -> Transaction {
        let viewPtr = btck_block_get_transaction_at(pointer, index)
        return Transaction(pointer: btck_transaction_copy(viewPtr))
    }

    /// The block header (owned — caller manages lifetime).
    public var header: BlockHeader {
        BlockHeader(pointer: btck_block_get_header(pointer))
    }

    /// The block hash (owned — caller manages lifetime).
    public var hash: BlockHash {
        BlockHash(pointer: btck_block_get_hash(pointer))
    }

    /// The consensus-serialized block bytes.
    public var data: Data {
        guard let result = serializeToData({ writer, userData in
            btck_block_to_bytes(pointer, writer, userData)
        }) else {
            preconditionFailure("Serialization of a valid Block must not fail")
        }
        return result
    }

    deinit {
        btck_block_destroy(pointer)
    }
}
