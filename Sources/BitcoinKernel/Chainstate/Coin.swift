//
//  Coin.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

internal import libbitcoinkernel

/// A UTXO — an unspent transaction output enriched with the metadata the
/// kernel needs to validate a spending transaction.
///
/// A `Coin` carries the ``TransactionOutput`` (amount + scriptPubKey) plus
/// two consensus-relevant metadata fields: the block height at which the
/// creating transaction was confirmed, and whether that transaction was a
/// coinbase (which gates the 100-block maturity rule).
///
/// Wraps the opaque `btck_Coin` type; `deinit` calls `btck_coin_destroy`
/// when the last Swift reference drops.
public final class Coin: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The block height at which the transaction creating this coin was
    /// confirmed on chain.
    ///
    /// Used by the kernel to enforce BIP 68 relative time locks and the
    /// 100-block coinbase-maturity rule. For a coin created in the genesis
    /// block, this is `0`.
    public var confirmationHeight: UInt32 {
        btck_coin_confirmation_height(pointer)
    }

    /// `true` if the coin was created by a coinbase (block-reward)
    /// transaction.
    ///
    /// Coinbase coins are subject to the 100-block maturity rule: they
    /// cannot be spent until 100 additional blocks have been confirmed on
    /// top of the block that created them. The kernel enforces this
    /// during ``ChainstateManager/processBlock(_:)``.
    public var isCoinbase: Bool {
        btck_coin_is_coinbase(pointer) != 0
    }

    /// The transaction output this coin represents — the amount (in
    /// satoshis) and the scriptPubKey that locks it. Returns an owned copy
    /// that outlives this ``Coin``.
    public var output: TransactionOutput {
        let viewPtr = btck_coin_get_output(pointer)
        return TransactionOutput(pointer: btck_transaction_output_copy(viewPtr))
    }

    deinit {
        btck_coin_destroy(pointer)
    }
}
