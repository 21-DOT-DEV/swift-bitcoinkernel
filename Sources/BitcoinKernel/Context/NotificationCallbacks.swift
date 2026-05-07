//
//  NotificationCallbacks.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

internal import libbitcoinkernel

/// Swift-friendly wrapper for kernel notification callbacks.
///
/// Populate the closure properties you care about, then pass to
/// ``ContextOptions/setNotifications(_:)``. The kernel takes ownership of
/// the callback state and releases it when the context is destroyed.
///
/// All callbacks are dispatched on kernel-internal threads.
public final class NotificationCallbacks: @unchecked Sendable {

    /// Called when the chain's tip is updated.
    ///
    /// - Parameters:
    ///   - state: Current synchronization state.
    ///   - entry: An owned snapshot of the new tip block tree entry.
    ///   - progress: Verification progress (0.0–1.0).
    public let blockTip: ((_ state: SynchronizationState, _ entry: BlockTreeEntrySnapshot, _ progress: Double) -> Void)?

    /// Called when a new best block header is added.
    ///
    /// - Parameters:
    ///   - state: Current synchronization state.
    ///   - height: Header chain height.
    ///   - timestamp: Header timestamp (Unix epoch seconds).
    ///   - presync: Whether this is a pre-sync header.
    public let headerTip: ((_ state: SynchronizationState, _ height: Int64, _ timestamp: Int64, _ presync: Bool) -> Void)?

    /// Reports on current block synchronization progress.
    ///
    /// - Parameters:
    ///   - title: Progress title.
    ///   - percentDone: Progress percentage (0–100).
    ///   - resumePossible: Whether the operation can be resumed.
    public let progress: ((_ title: String, _ percentDone: Int32, _ resumePossible: Bool) -> Void)?

    /// A warning issued during validation.
    ///
    /// - Parameters:
    ///   - warning: The warning type.
    ///   - message: Human-readable warning message.
    public let warningSet: ((_ warning: Warning, _ message: String) -> Void)?

    /// A previous warning condition is no longer active.
    ///
    /// - Parameter warning: The warning type that was cleared.
    public let warningUnset: ((_ warning: Warning) -> Void)?

    /// An error encountered when flushing data to disk.
    ///
    /// - Parameter message: Human-readable error message.
    public let flushError: ((_ message: String) -> Void)?

    /// An unrecoverable system error encountered by the library.
    ///
    /// - Parameter message: Human-readable error message.
    public let fatalError: ((_ message: String) -> Void)?

    /// Creates notification callbacks.
    ///
    /// Set only the callbacks you need; unset callbacks are ignored.
    /// All closures are captured at init time and cannot be changed later.
    public init(
        blockTip: ((_ state: SynchronizationState, _ entry: BlockTreeEntrySnapshot, _ progress: Double) -> Void)? = nil,
        headerTip: ((_ state: SynchronizationState, _ height: Int64, _ timestamp: Int64, _ presync: Bool) -> Void)? = nil,
        progress: ((_ title: String, _ percentDone: Int32, _ resumePossible: Bool) -> Void)? = nil,
        warningSet: ((_ warning: Warning, _ message: String) -> Void)? = nil,
        warningUnset: ((_ warning: Warning) -> Void)? = nil,
        flushError: ((_ message: String) -> Void)? = nil,
        fatalError: ((_ message: String) -> Void)? = nil
    ) {
        self.blockTip = blockTip
        self.headerTip = headerTip
        self.progress = progress
        self.warningSet = warningSet
        self.warningUnset = warningUnset
        self.flushError = flushError
        self.fatalError = fatalError
    }

    /// Builds the C callback struct, transferring ownership of `self` to the kernel.
    ///
    /// After calling this, do **not** hold a strong reference to `self` —
    /// the kernel owns it and will free it via `user_data_destroy`.
    func makeCCallbacks() -> btck_NotificationInterfaceCallbacks {
        var cbs = btck_NotificationInterfaceCallbacks()
        cbs.user_data = Unmanaged.passRetained(self).toOpaque()
        cbs.user_data_destroy = { userData in
            guard let userData else { return }
            Unmanaged<NotificationCallbacks>.fromOpaque(userData).release()
        }
        cbs.block_tip = { userData, state, entry, progress in
            guard let userData, let entry else { return }
            let s = Unmanaged<NotificationCallbacks>.fromOpaque(userData).takeUnretainedValue()
            let syncState = SynchronizationState(rawValue: state) ?? .postInit
            let snapshot = BlockTreeEntrySnapshot(
                height: btck_block_tree_entry_get_height(entry),
                blockHash: BlockHash(pointer: btck_block_hash_copy(btck_block_tree_entry_get_block_hash(entry))),
                blockHeader: BlockHeader(pointer: btck_block_tree_entry_get_block_header(entry))
            )
            s.blockTip?(syncState, snapshot, progress)
        }
        cbs.header_tip = { userData, state, height, timestamp, presync in
            guard let userData else { return }
            let s = Unmanaged<NotificationCallbacks>.fromOpaque(userData).takeUnretainedValue()
            let syncState = SynchronizationState(rawValue: state) ?? .postInit
            s.headerTip?(syncState, height, timestamp, presync != 0)
        }
        cbs.progress = { userData, title, titleLen, percentDone, resumePossible in
            guard let userData else { return }
            let s = Unmanaged<NotificationCallbacks>.fromOpaque(userData).takeUnretainedValue()
            let titleStr: String
            if let title {
                titleStr = String(
                    decoding: UnsafeBufferPointer(
                        start: UnsafePointer<UInt8>(OpaquePointer(title)),
                        count: titleLen
                    ),
                    as: UTF8.self
                )
            } else {
                titleStr = ""
            }
            s.progress?(titleStr, percentDone, resumePossible != 0)
        }
        cbs.warning_set = { userData, warning, message, messageLen in
            guard let userData else { return }
            let s = Unmanaged<NotificationCallbacks>.fromOpaque(userData).takeUnretainedValue()
            let w = Warning(rawValue: warning) ?? .unknownNewRulesActivated
            let msg: String
            if let message {
                msg = String(
                    decoding: UnsafeBufferPointer(
                        start: UnsafePointer<UInt8>(OpaquePointer(message)),
                        count: messageLen
                    ),
                    as: UTF8.self
                )
            } else {
                msg = ""
            }
            s.warningSet?(w, msg)
        }
        cbs.warning_unset = { userData, warning in
            guard let userData else { return }
            let s = Unmanaged<NotificationCallbacks>.fromOpaque(userData).takeUnretainedValue()
            let w = Warning(rawValue: warning) ?? .unknownNewRulesActivated
            s.warningUnset?(w)
        }
        cbs.flush_error = { userData, message, messageLen in
            guard let userData else { return }
            let s = Unmanaged<NotificationCallbacks>.fromOpaque(userData).takeUnretainedValue()
            let msg: String
            if let message {
                msg = String(
                    decoding: UnsafeBufferPointer(
                        start: UnsafePointer<UInt8>(OpaquePointer(message)),
                        count: messageLen
                    ),
                    as: UTF8.self
                )
            } else {
                msg = ""
            }
            s.flushError?(msg)
        }
        cbs.fatal_error = { userData, message, messageLen in
            guard let userData else { return }
            let s = Unmanaged<NotificationCallbacks>.fromOpaque(userData).takeUnretainedValue()
            let msg: String
            if let message {
                msg = String(
                    decoding: UnsafeBufferPointer(
                        start: UnsafePointer<UInt8>(OpaquePointer(message)),
                        count: messageLen
                    ),
                    as: UTF8.self
                )
            } else {
                msg = ""
            }
            s.fatalError?(msg)
        }
        return cbs
    }
}
