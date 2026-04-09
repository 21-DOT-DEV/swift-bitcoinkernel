internal import libbitcoinkernel
import Foundation

/// A Bitcoin block header (80 bytes: version, prev hash, merkle root, time, bits, nonce).
///
/// Wraps the opaque `btck_BlockHeader` type. ARC via `deinit` calls
/// `btck_block_header_destroy` when the last reference drops.
public final class BlockHeader: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Creates a block header from serialized data.
    ///
    /// - Parameter data: Exactly 80 bytes of serialized header data.
    /// - Throws: ``KernelError/blockHeaderCreationFailed`` if parsing fails.
    public init(_ data: Data) throws {
        guard let ptr = data.withUnsafeBytes({ rawBuf -> OpaquePointer? in
            guard let baseAddress = rawBuf.baseAddress else { return nil }
            return btck_block_header_create(baseAddress, rawBuf.count)
        }) else {
            throw KernelError.blockHeaderCreationFailed
        }
        self.pointer = ptr
    }

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The block hash (owned — caller manages lifetime).
    public var hash: BlockHash {
        BlockHash(pointer: btck_block_header_get_hash(pointer))
    }

    /// The previous block's hash (owned copy).
    public var previousHash: BlockHash {
        let viewPtr = btck_block_header_get_prev_hash(pointer)
        return BlockHash(pointer: btck_block_hash_copy(viewPtr))
    }

    /// The block timestamp (Unix epoch seconds).
    public var timestamp: UInt32 {
        btck_block_header_get_timestamp(pointer)
    }

    /// The difficulty target in compact format (nBits).
    public var bits: UInt32 {
        btck_block_header_get_bits(pointer)
    }

    /// The block version.
    public var version: Int32 {
        btck_block_header_get_version(pointer)
    }

    /// The nonce used for proof-of-work.
    public var nonce: UInt32 {
        btck_block_header_get_nonce(pointer)
    }

    deinit {
        btck_block_header_destroy(pointer)
    }
}
