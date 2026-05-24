//
//  BlockTreeEntry.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

internal import libbitcoinkernel

/// An entry in the block tree (block index) — a block the kernel has
/// validated, whether on the active chain or on a side chain.
///
/// Obtained from ``ChainstateManager/bestEntry``,
/// ``ChainstateManager/blockTreeEntry(byHash:)``, or
/// ``Chain/entry(atHeight:)``. Exposes height, hash, header, and walkable
/// parent pointer (``previous``). Use ``Chain/contains(_:)`` to test
/// whether an entry is on the active chain.
///
/// A **view type**: its lifetime is tied to the ``ChainstateManager`` that
/// produced it. Retains the manager to keep the C pointer valid; `deinit`
/// performs no kernel destruction. For storing entry data past the
/// manager's lifetime, promote to ``BlockTreeEntrySnapshot``.
public final class BlockTreeEntry: @unchecked Sendable {
    let pointer: OpaquePointer
    /// Retains the owning manager so the C pointer stays valid.
    private let _owner: AnyObject?

    /// Internal initializer from an unowned C pointer.
    init(pointer: OpaquePointer, owner: AnyObject? = nil) {
        self.pointer = pointer
        self._owner = owner
    }

    /// The block's height above genesis (`0` for genesis).
    public var height: Int32 {
        btck_block_tree_entry_get_height(pointer)
    }

    /// The block's hash as an owned ``BlockHash``. Safe to store past this
    /// entry's lifetime (the hash copy outlives it; the entry does not).
    public var blockHash: BlockHash {
        let viewPtr = btck_block_tree_entry_get_block_hash(pointer)
        return BlockHash(pointer: btck_block_hash_copy(viewPtr))
    }

    /// The 80-byte ``BlockHeader`` as an owned copy. Safe to store past
    /// this entry's lifetime.
    public var blockHeader: BlockHeader {
        BlockHeader(pointer: btck_block_tree_entry_get_block_header(pointer))
    }

    /// The parent block's entry in the block tree, or `nil` for the
    /// genesis block.
    ///
    /// Chain the pointer to walk backwards: `entry.previous?.previous…`
    /// unwinds the chain one block at a time until genesis. Used for
    /// fork-point detection during reorg handling.
    public var previous: BlockTreeEntry? {
        guard let ptr = btck_block_tree_entry_get_previous(pointer) else {
            return nil
        }
        return BlockTreeEntry(pointer: ptr, owner: _owner)
    }

    /// Whether two entries reference the same block.
    ///
    /// Delegates to the kernel's `btck_block_tree_entry_equals`. Use when
    /// comparing entries obtained through different navigation paths (by
    /// hash, by height, via `previous`).
    public func equals(_ other: BlockTreeEntry) -> Bool {
        btck_block_tree_entry_equals(pointer, other.pointer) != 0
    }
}
