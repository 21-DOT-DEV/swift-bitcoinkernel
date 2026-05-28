//
//  Transaction.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

internal import libbitcoinkernel
import Foundation

/// A Bitcoin transaction — the consensus-layer value type that moves
/// coins from one set of scriptPubKeys to another.
///
/// Construct from network/disk bytes via ``init(_:)`` for stand-alone
/// parsing, or obtain from a ``Block`` via ``Block/transaction(at:)``.
/// The kernel parses, structurally validates, and produces an opaque
/// handle; full consensus validation (witness checks, signature
/// verification, script execution) happens through script verification
/// APIs and ``ChainstateManager/processBlock(_:)``.
///
/// Wraps the opaque `btck_Transaction` type; `deinit` calls
/// `btck_transaction_destroy` when the last Swift reference drops.
public final class Transaction: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Creates a transaction from serialized (consensus-encoded) data.
    ///
    /// - Parameter data: The raw transaction bytes.
    /// - Throws: ``KernelError/transactionCreationFailed`` if parsing fails.
    public init(_ data: Data) throws {
        guard let ptr = data.withUnsafeBytes({ rawBuf -> OpaquePointer? in
            guard let baseAddress = rawBuf.baseAddress else { return nil }
            return btck_transaction_create(baseAddress, rawBuf.count)
        }) else {
            throw KernelError.transactionCreationFailed
        }
        self.pointer = ptr
    }

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The number of outputs in this transaction — the destinations
    /// and amounts being paid. Always ≥ 1.
    public var outputCount: Int {
        btck_transaction_count_outputs(pointer)
    }

    /// The number of inputs in this transaction — the previous-outputs
    /// being spent. `0` for a coinbase transaction; otherwise ≥ 1.
    public var inputCount: Int {
        btck_transaction_count_inputs(pointer)
    }

    /// Returns the output at the given index (owned copy).
    ///
    /// - Parameter index: Zero-based output index.
    /// - Precondition: `index` must be in `0..<outputCount`.
    public func output(at index: Int) -> TransactionOutput {
        let viewPtr = btck_transaction_get_output_at(pointer, index)
        return TransactionOutput(pointer: btck_transaction_output_copy(viewPtr))
    }

    /// Returns the input at the given index (owned copy).
    ///
    /// - Parameter index: Zero-based input index.
    /// - Precondition: `index` must be in `0..<inputCount`.
    public func input(at index: Int) -> TransactionInput {
        let viewPtr = btck_transaction_get_input_at(pointer, index)
        return TransactionInput(pointer: btck_transaction_input_copy(viewPtr))
    }

    /// The transaction ID — double-SHA256 of the transaction's
    /// non-witness bytes. Returns an owned copy that outlives this
    /// transaction.
    ///
    /// TXID vs. WTXID distinction: this is the TXID (excludes witness
    /// data), the stable identifier used by `prevout.hash` references.
    /// Witness transactions additionally have a WTXID that includes
    /// witness data — the kernel does not currently expose WTXID on this
    /// type.
    public var txid: Txid {
        let viewPtr = btck_transaction_get_txid(pointer)
        return Txid(pointer: btck_txid_copy(viewPtr))
    }

    /// The consensus-serialized transaction bytes — the round-trip of
    /// ``init(_:)``. Always succeeds for a valid transaction;
    /// serialization failures indicate a kernel bug.
    public var data: Data {
        guard let result = serializeToData({ writer, userData in
            btck_transaction_to_bytes(pointer, writer, userData)
        }) else {
            preconditionFailure("Serialization of a valid Transaction must not fail")
        }
        return result
    }

    deinit {
        btck_transaction_destroy(pointer)
    }
}
