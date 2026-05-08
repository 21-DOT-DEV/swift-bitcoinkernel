//
//  Chain.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

internal import libbitcoinkernel

/// A view of the active blockchain — the unbroken sequence of blocks from
/// genesis to the chainstate's current tip.
///
/// Obtained via ``ChainstateManager/activeChain``. Exposes height-indexed
/// lookups (``entry(atHeight:)``) and active-chain membership testing
/// (``contains(_:)``) — useful for distinguishing a block that's on the
/// current chain from one on a side chain, after a reorg.
///
/// A **view type**: its lifetime is tied to the ``ChainstateManager`` that
/// produced it. Retains the manager to keep the C pointer valid; `deinit`
/// performs no kernel destruction.
public final class Chain: @unchecked Sendable {
    let pointer: OpaquePointer
    /// Retains the owning manager so the C pointer stays valid.
    private let _owner: AnyObject?

    /// Internal initializer from an unowned C pointer.
    init(pointer: OpaquePointer, owner: AnyObject? = nil) {
        self.pointer = pointer
        self._owner = owner
    }

    /// The height of the tip of the active chain (`0` = genesis).
    ///
    /// Equals `manager.bestEntry.height`. Refresh periodically during a
    /// sync run — the value advances each time
    /// ``ChainstateManager/processBlock(_:)`` extends the chain.
    public var height: Int32 {
        btck_chain_get_height(pointer)
    }

    /// Retrieves a block tree entry by its height on the active chain.
    ///
    /// Returns `nil` for heights greater than ``height`` or negative
    /// heights. Note that this is height-on-the-active-chain lookup; use
    /// ``ChainstateManager/blockTreeEntry(byHash:)`` to access blocks on
    /// side chains.
    ///
    /// - Parameter height: The block height (`0` for genesis).
    /// - Returns: The active-chain entry at that height, or `nil` if out of
    ///   range.
    public func entry(atHeight height: Int32) -> BlockTreeEntry? {
        guard let ptr = btck_chain_get_by_height(pointer, height) else {
            return nil
        }
        return BlockTreeEntry(pointer: ptr, owner: _owner)
    }

    /// Whether the active chain contains the given block tree entry —
    /// distinguishes blocks on the main chain from blocks on side chains.
    ///
    /// - Parameter entry: A block tree entry, typically returned from
    ///   ``ChainstateManager/blockTreeEntry(byHash:)`` (which finds any
    ///   entry) or from earlier calls to ``entry(atHeight:)``.
    /// - Returns: `true` if `entry` is on the current active chain.
    public func contains(_ entry: BlockTreeEntry) -> Bool {
        btck_chain_contains(pointer, entry.pointer) != 0
    }
}
