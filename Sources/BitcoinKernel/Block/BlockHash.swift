internal import libbitcoinkernel
import Foundation

/// A 32-byte block hash (double-SHA256 of the block header).
///
/// Wraps the opaque `btck_BlockHash` type. ARC via `deinit` calls
/// `btck_block_hash_destroy` when the last reference drops.
public final class BlockHash: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Creates a block hash from raw 32-byte data.
    ///
    /// - Parameter data: Exactly 32 bytes of hash data.
    /// - Precondition: `data.count == 32`.
    public init(_ data: Data) {
        precondition(data.count == 32, "BlockHash requires exactly 32 bytes")
        self.pointer = data.withUnsafeBytes { rawBuf in
            guard let baseAddress = rawBuf.baseAddress else {
                preconditionFailure("BlockHash requires exactly 32 bytes")
            }
            return btck_block_hash_create(baseAddress.assumingMemoryBound(to: UInt8.self))
        }
    }

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The raw 32-byte hash data.
    public var data: Data {
        var output = [UInt8](repeating: 0, count: 32)
        output.withUnsafeMutableBufferPointer { buf in
            guard let baseAddress = buf.baseAddress else { return }
            btck_block_hash_to_bytes(pointer, baseAddress)
        }
        return Data(output)
    }

    /// Whether this block hash equals another.
    public func equals(_ other: BlockHash) -> Bool {
        btck_block_hash_equals(pointer, other.pointer) != 0
    }

    deinit {
        btck_block_hash_destroy(pointer)
    }
}
