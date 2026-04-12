internal import libbitcoinkernel
import Foundation

/// A script pubkey (locking script) for a transaction output.
///
/// Wraps the opaque `btck_ScriptPubkey` type. ARC via `deinit` calls
/// `btck_script_pubkey_destroy` when the last reference drops.
public final class ScriptPubkey: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Creates a script pubkey from serialized script data.
    ///
    /// - Parameter data: The raw script bytes.
    public init(_ data: Data) {
        self.pointer = data.withUnsafeBytes { rawBuf in
            guard let baseAddress = rawBuf.baseAddress else {
                preconditionFailure("ScriptPubkey requires non-empty data")
            }
            return btck_script_pubkey_create(baseAddress, rawBuf.count)
        }
    }

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The serialized script bytes.
    public var data: Data {
        guard let result = serializeToData({ writer, userData in
            btck_script_pubkey_to_bytes(pointer, writer, userData)
        }) else {
            preconditionFailure("Serialization of a valid ScriptPubkey must not fail")
        }
        return result
    }

    /// Verifies whether a transaction input spends this script pubkey.
    ///
    /// ```swift
    /// let script = ScriptPubkey(outputScriptData)
    /// let (valid, status) = script.verify(
    ///     amount: 50_000,
    ///     transaction: spendingTx,
    ///     inputIndex: 0
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - amount: The amount associated with this output (used when witness flag is set).
    ///   - transaction: The spending transaction.
    ///   - precomputedData: Pre-computed transaction data (required for taproot).
    ///   - inputIndex: Index of the spending input in the transaction.
    ///   - flags: Script verification flags controlling validation.
    /// - Returns: A tuple of `(valid, status)` where `valid` indicates if the
    ///   script passed, and `status` provides details on failure.
    public func verify(
        amount: Int64,
        transaction: Transaction,
        precomputedData: PrecomputedTransactionData? = nil,
        inputIndex: UInt32,
        flags: ScriptVerificationFlags = .all
    ) -> (valid: Bool, status: ScriptVerifyStatus) {
        var rawStatus: UInt8 = 0
        let result = btck_script_pubkey_verify(
            pointer,
            amount,
            transaction.pointer,
            precomputedData?.pointer,
            UInt32(inputIndex),
            flags.rawValue,
            &rawStatus
        )
        let status = ScriptVerifyStatus(rawValue: rawStatus) ?? .ok
        return (result == 1, status)
    }

    deinit {
        btck_script_pubkey_destroy(pointer)
    }
}
