//
//  TransactionOutPoint.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

internal import libbitcoinkernel

/// A reference to a specific output of a previous transaction — a
/// `(txid, output-index)` pair used by ``TransactionInput`` to identify
/// the UTXO being spent.
///
/// Outpoints are obtained from a ``TransactionInput`` via
/// ``TransactionInput/outPoint``; there is no public `create`
/// initializer.
///
/// The coinbase-transaction sentinel is `txid == all-zeros` and
/// `index == 0xFFFFFFFF` — no previous transaction is being referenced.
///
/// Wraps the opaque `btck_TransactionOutPoint` type; `deinit` calls
/// `btck_transaction_out_point_destroy` when the last Swift reference
/// drops.
public final class TransactionOutPoint: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The zero-based index of the output in the referenced transaction.
    /// `0xFFFFFFFF` is the coinbase sentinel.
    public var index: UInt32 {
        btck_transaction_out_point_get_index(pointer)
    }

    /// The TXID of the referenced transaction as an owned copy. For
    /// coinbase outpoints, all 32 bytes are zero.
    public var txid: Txid {
        let viewPtr = btck_transaction_out_point_get_txid(pointer)
        return Txid(pointer: btck_txid_copy(viewPtr))
    }

    deinit {
        btck_transaction_out_point_destroy(pointer)
    }
}
