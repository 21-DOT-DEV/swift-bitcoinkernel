//
//  PrecomputedTransactionData.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

internal import libbitcoinkernel

/// Cached per-transaction data that speeds up repeated script
/// verification — most importantly, the BIP-341 sighash components a
/// taproot spend uses (`hashPrevouts`, `hashAmounts`,
/// `hashScriptPubkeys`, `hashSequences`, `hashOutputs`) that would
/// otherwise be recomputed for every input.
///
/// Construct once per transaction, then reuse across every
/// ``ScriptPubkey/verify(amount:transaction:precomputedData:inputIndex:flags:)``
/// call for that transaction. For non-taproot verification the
/// `spentOutputs` argument is optional; for taproot it is required.
///
/// Wraps the opaque `btck_PrecomputedTransactionData` type; `deinit`
/// calls `btck_precomputed_transaction_data_destroy` when the last Swift
/// reference drops.
public final class PrecomputedTransactionData: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Creates precomputed data for script verification.
    ///
    /// - Parameters:
    ///   - transaction: The spending transaction to pre-compute hashes for.
    ///   - spentOutputs: The outputs being spent, one per transaction
    ///     input in input order. Required when verifying under the
    ///     ``ScriptVerificationFlags/taproot`` flag; optional (pass `nil`)
    ///     for non-taproot verification.
    /// - Throws: ``KernelError/precomputedDataCreationFailed`` when the
    ///   spent-outputs count mismatches `transaction.inputCount`, when the
    ///   transaction is malformed, or when the kernel rejects the combined
    ///   input.
    public init(transaction: Transaction, spentOutputs: [TransactionOutput]? = nil) throws {
        let txPtr = transaction.pointer

        if let spentOutputs {
            var ptrs: [OpaquePointer?] = spentOutputs.map { $0.pointer }
            guard let ptr = ptrs.withUnsafeMutableBufferPointer({ buf in
                btck_precomputed_transaction_data_create(
                    txPtr,
                    buf.baseAddress,
                    buf.count
                )
            }) else {
                throw KernelError.precomputedDataCreationFailed
            }
            self.pointer = ptr
        } else {
            guard let ptr = btck_precomputed_transaction_data_create(txPtr, nil, 0) else {
                throw KernelError.precomputedDataCreationFailed
            }
            self.pointer = ptr
        }
    }

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        btck_precomputed_transaction_data_destroy(pointer)
    }
}
