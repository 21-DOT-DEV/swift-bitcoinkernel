//
//  ValidationInterfaceCallbacks.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

internal import libbitcoinkernel

/// Swift-friendly wrapper for validation interface callbacks.
///
/// Populate the closure properties you care about, then pass to
/// ``ContextOptions/setValidationInterface(_:)``. The kernel takes ownership
/// of the callback state and releases it when the context is destroyed.
///
/// All callbacks are dispatched on kernel-internal threads and **block
/// further validation** while executing — keep handlers fast.
public final class ValidationInterfaceCallbacks: @unchecked Sendable {

    /// Called when a new block has been fully validated.
    ///
    /// - Parameters:
    ///   - block: The validated block (owned copy).
    ///   - state: The validation state result (owned copy).
    public let blockChecked: ((_ block: Block, _ state: BlockValidationState) -> Void)?

    /// Called when a new block extends the header chain with valid PoW.
    ///
    /// - Parameters:
    ///   - block: The block with valid proof-of-work (owned copy).
    ///   - entry: An owned snapshot of the block tree entry.
    public let powValidBlock: ((_ block: Block, _ entry: BlockTreeEntrySnapshot) -> Void)?

    /// Called when a valid block has been connected to the best chain.
    ///
    /// - Parameters:
    ///   - block: The connected block (owned copy).
    ///   - entry: An owned snapshot of the block tree entry.
    public let blockConnected: ((_ block: Block, _ entry: BlockTreeEntrySnapshot) -> Void)?

    /// Called during a re-org when a block has been removed from the best chain.
    ///
    /// - Parameters:
    ///   - block: The disconnected block (owned copy).
    ///   - entry: An owned snapshot of the block tree entry.
    public let blockDisconnected: ((_ block: Block, _ entry: BlockTreeEntrySnapshot) -> Void)?

    /// Creates validation interface callbacks.
    ///
    /// Set only the callbacks you need; unset callbacks are ignored.
    /// All closures are captured at init time and cannot be changed later.
    ///
    /// - Parameters:
    ///   - blockChecked: Handler for blocks that have been fully validated. See ``blockChecked``.
    ///   - powValidBlock: Handler for blocks with valid proof-of-work added to the header chain. See ``powValidBlock``.
    ///   - blockConnected: Handler for blocks connected to the best chain. See ``blockConnected``.
    ///   - blockDisconnected: Handler for blocks removed from the best chain during a re-org. See ``blockDisconnected``.
    public init(
        blockChecked: ((_ block: Block, _ state: BlockValidationState) -> Void)? = nil,
        powValidBlock: ((_ block: Block, _ entry: BlockTreeEntrySnapshot) -> Void)? = nil,
        blockConnected: ((_ block: Block, _ entry: BlockTreeEntrySnapshot) -> Void)? = nil,
        blockDisconnected: ((_ block: Block, _ entry: BlockTreeEntrySnapshot) -> Void)? = nil
    ) {
        self.blockChecked = blockChecked
        self.powValidBlock = powValidBlock
        self.blockConnected = blockConnected
        self.blockDisconnected = blockDisconnected
    }

    /// Builds the C callback struct, transferring ownership of `self` to the kernel.
    func makeCCallbacks() -> btck_ValidationInterfaceCallbacks {
        var cbs = btck_ValidationInterfaceCallbacks()
        cbs.user_data = Unmanaged.passRetained(self).toOpaque()
        cbs.user_data_destroy = { userData in
            guard let userData else { return }
            Unmanaged<ValidationInterfaceCallbacks>.fromOpaque(userData).release()
        }
        cbs.block_checked = { userData, block, state in
            guard let userData, let block, let state else { return }
            let s = Unmanaged<ValidationInterfaceCallbacks>.fromOpaque(userData).takeUnretainedValue()
            s.blockChecked?(
                Block(pointer: btck_block_copy(block)),
                BlockValidationState(pointer: btck_block_validation_state_copy(state))
            )
        }
        cbs.pow_valid_block = { userData, block, entry in
            guard let userData, let block, let entry else { return }
            let s = Unmanaged<ValidationInterfaceCallbacks>.fromOpaque(userData).takeUnretainedValue()
            let snapshot = BlockTreeEntrySnapshot(
                height: btck_block_tree_entry_get_height(entry),
                blockHash: BlockHash(pointer: btck_block_hash_copy(btck_block_tree_entry_get_block_hash(entry))),
                blockHeader: BlockHeader(pointer: btck_block_tree_entry_get_block_header(entry))
            )
            s.powValidBlock?(
                Block(pointer: btck_block_copy(block)),
                snapshot
            )
        }
        cbs.block_connected = { userData, block, entry in
            guard let userData, let block, let entry else { return }
            let s = Unmanaged<ValidationInterfaceCallbacks>.fromOpaque(userData).takeUnretainedValue()
            let snapshot = BlockTreeEntrySnapshot(
                height: btck_block_tree_entry_get_height(entry),
                blockHash: BlockHash(pointer: btck_block_hash_copy(btck_block_tree_entry_get_block_hash(entry))),
                blockHeader: BlockHeader(pointer: btck_block_tree_entry_get_block_header(entry))
            )
            s.blockConnected?(
                Block(pointer: btck_block_copy(block)),
                snapshot
            )
        }
        cbs.block_disconnected = { userData, block, entry in
            guard let userData, let block, let entry else { return }
            let s = Unmanaged<ValidationInterfaceCallbacks>.fromOpaque(userData).takeUnretainedValue()
            let snapshot = BlockTreeEntrySnapshot(
                height: btck_block_tree_entry_get_height(entry),
                blockHash: BlockHash(pointer: btck_block_hash_copy(btck_block_tree_entry_get_block_hash(entry))),
                blockHeader: BlockHeader(pointer: btck_block_tree_entry_get_block_header(entry))
            )
            s.blockDisconnected?(
                Block(pointer: btck_block_copy(block)),
                snapshot
            )
        }
        return cbs
    }
}
