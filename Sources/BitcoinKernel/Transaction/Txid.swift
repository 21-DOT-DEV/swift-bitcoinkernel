//
//  Txid.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

internal import libbitcoinkernel
import Foundation

/// A 32-byte transaction identifier — double-SHA256 of a transaction's
/// non-witness serialization.
///
/// TXID (this type) is stable across witness malleation and is what
/// `prevout.hash` fields reference. WTXID (not exposed on this type)
/// additionally includes witness data. Like block hashes, TXIDs are
/// stored internally in kernel byte order — reverse for the display-order
/// hex used by block explorers.
///
/// Obtained via ``Transaction/txid`` or ``TransactionOutPoint/txid``;
/// there is no public `create` initializer.
///
/// Wraps the opaque `btck_Txid` type; `deinit` calls `btck_txid_destroy`
/// when the last Swift reference drops.
public final class Txid: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The raw 32-byte TXID in internal (kernel) byte order. Reverse the
    /// byte order before hex-encoding for display in a block explorer.
    public var data: Data {
        var output = [UInt8](repeating: 0, count: 32)
        output.withUnsafeMutableBufferPointer { buf in
            guard let baseAddress = buf.baseAddress else { return }
            btck_txid_to_bytes(pointer, baseAddress)
        }
        return Data(output)
    }

    /// Whether two TXIDs are byte-for-byte equal. Delegates to the
    /// kernel's `btck_txid_equals` for the canonical comparison.
    public func equals(_ other: Txid) -> Bool {
        btck_txid_equals(pointer, other.pointer) != 0
    }

    deinit {
        btck_txid_destroy(pointer)
    }
}
