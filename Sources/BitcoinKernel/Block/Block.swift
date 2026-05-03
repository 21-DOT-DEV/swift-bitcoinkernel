internal import libbitcoinkernel
import Foundation

/// A Bitcoin block — an 80-byte ``BlockHeader`` plus its list of
/// ``Transaction`` values, structurally validated by the kernel on
/// construction.
///
/// Construct from consensus-serialized bytes (network or disk format) via
/// ``init(_:)``. The kernel parses, sanity-checks structure, and produces
/// an opaque handle; downstream consensus validation happens through
/// ``ChainstateManager/processBlock(_:)``.
///
/// Wraps the opaque `btck_Block` type; `deinit` calls `btck_block_destroy`
/// when the last Swift reference drops.
public final class Block: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Parses a block from its consensus-serialized bytes.
    ///
    /// The input is the same byte layout used on the Bitcoin P2P wire and
    /// in `blk*.dat` files: header + varint(tx count) + transactions.
    /// Parsing is structural only — the kernel checks the block is
    /// well-formed, not that it passes consensus rules or proof-of-work.
    ///
    /// - Parameter data: Consensus-serialized block bytes.
    /// - Throws: ``KernelError/blockCreationFailed`` when the bytes fail
    ///   to decode (wrong magic, truncated, invalid varint, malformed
    ///   transactions).
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

    /// The number of transactions in this block. Always ≥ 1 — every valid
    /// block carries at least a coinbase.
    public var transactionCount: Int {
        btck_block_count_transactions(pointer)
    }

    /// Returns the transaction at the given index as an owned
    /// ``Transaction`` (safe to store past this block's lifetime).
    ///
    /// Index `0` is always the coinbase transaction. Non-coinbase
    /// transactions follow in block order (typically ascending fee rate
    /// for miner-assembled blocks, but this is convention — the consensus
    /// rules don't require it).
    ///
    /// - Parameter index: Zero-based transaction index.
    /// - Precondition: `index` must be in `0..<transactionCount`.
    public func transaction(at index: Int) -> Transaction {
        let viewPtr = btck_block_get_transaction_at(pointer, index)
        return Transaction(pointer: btck_transaction_copy(viewPtr))
    }

    /// The 80-byte ``BlockHeader`` carrying version, previous-block hash,
    /// merkle root, timestamp, nBits, and nonce. Returns an owned copy
    /// that outlives this block.
    public var header: BlockHeader {
        BlockHeader(pointer: btck_block_get_header(pointer))
    }

    /// The block's hash — double-SHA256 of the 80-byte header.
    ///
    /// Equivalent to `self.header.hash`. Returns an owned copy that
    /// outlives this block. The hash is in internal (kernel) byte order
    /// — reverse it for display-order hex.
    public var hash: BlockHash {
        BlockHash(pointer: btck_block_get_hash(pointer))
    }

    /// The consensus-serialized block bytes — the round-trip of
    /// ``init(_:)``.
    ///
    /// Always succeeds for a valid ``Block`` (the kernel only produces
    /// blocks it could serialize back out); serialization failures
    /// indicate a kernel bug and trap via `preconditionFailure`.
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
