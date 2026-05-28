//
//  TransactionOutput.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

internal import libbitcoinkernel

/// A transaction output — the paid amount (``amount`` in satoshis) plus
/// the ``ScriptPubkey`` that locks it.
///
/// Construct via ``init(scriptPubkey:amount:)`` to fabricate an output
/// (e.g., for script verification tests); obtain from a ``Transaction``
/// via ``Transaction/output(at:)`` to read an output off an existing
/// transaction.
///
/// Wraps the opaque `btck_TransactionOutput` type; `deinit` calls
/// `btck_transaction_output_destroy` when the last Swift reference drops.
public final class TransactionOutput: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Creates a transaction output from a script pubkey and amount.
    ///
    /// Useful for fabricating synthetic outputs in test vectors — e.g.,
    /// preparing the `spentOutputs` argument for
    /// ``ScriptPubkey/verify(amount:transaction:precomputedData:inputIndex:flags:)``.
    ///
    /// - Parameters:
    ///   - scriptPubkey: The locking script for this output.
    ///   - amount: The value in satoshis. Valid range is `0...2_100_000_000_000_000`
    ///     (the 21 M BTC cap × 10⁸ satoshis/BTC). The kernel does not
    ///     reject over-cap values at construction — consensus does.
    public init(scriptPubkey: ScriptPubkey, amount: Int64) {
        self.pointer = btck_transaction_output_create(scriptPubkey.pointer, amount)
    }

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The script pubkey of this output — the locking script that a
    /// spending transaction must satisfy. Returns an owned copy that
    /// outlives this output.
    public var scriptPubkey: ScriptPubkey {
        let viewPtr = btck_transaction_output_get_script_pubkey(pointer)
        return ScriptPubkey(pointer: btck_script_pubkey_copy(viewPtr))
    }

    /// The output amount in satoshis (1 satoshi = 10⁻⁸ BTC). Signed
    /// `Int64` to match Bitcoin Core's `CAmount`, though negative values
    /// are never valid in consensus.
    public var amount: Int64 {
        btck_transaction_output_get_amount(pointer)
    }

    deinit {
        btck_transaction_output_destroy(pointer)
    }
}
