//
//  KernelError.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Errors from the Bitcoin kernel C API.
///
/// The kernel C API is deliberately minimal: `btck_*_create` functions
/// return `NULL` on failure with no error code, no message, and no way to
/// distinguish causes programmatically. ``KernelError`` preserves the only
/// information the C API actually provides — which call failed — and
/// invites callers to re-run under a ``LoggingConnection`` to see the
/// underlying reason in kernel log output.
public enum KernelError: Error, Sendable, CaseIterable, Equatable, CustomStringConvertible, LocalizedError {
    /// `btck_context_create` returned null.
    ///
    /// Typically caused by invalid chain parameters or callback setup.
    /// Enable kernel logging before retrying to see the underlying reason.
    case contextCreationFailed

    /// `btck_logging_connection_create` returned null.
    ///
    /// Thrown by ``LoggingConnection/init(callback:)``. Usually indicates
    /// that ``disableLogging()`` was already called — logging cannot be
    /// re-enabled for the lifetime of the process after disabling.
    case loggingConnectionFailed

    /// `btck_transaction_create` returned null — the input bytes did not
    /// decode as a valid Bitcoin transaction.
    case transactionCreationFailed

    /// `btck_block_create` returned null — the input bytes did not decode
    /// as a valid Bitcoin block (wrong magic, truncated data, invalid
    /// varint, etc.).
    case blockCreationFailed

    /// `btck_block_header_create` returned null — the input was not
    /// exactly 80 bytes of a valid serialized header.
    case blockHeaderCreationFailed

    /// `btck_precomputed_transaction_data_create` returned null, typically
    /// because the spent-outputs argument did not match the transaction's
    /// input count or a witness requirement.
    case precomputedDataCreationFailed

    /// `btck_chainstate_manager_options_create` returned null.
    ///
    /// Most commonly caused by the data directory being inaccessible
    /// (missing, not writable, on a filesystem that doesn't support the
    /// required operations).
    case chainstateManagerOptionsCreationFailed

    /// `btck_chainstate_manager_create` returned null.
    ///
    /// Indicates that opening the LevelDB block-index or chainstate
    /// databases failed. Common causes: another process holds the lock,
    /// the on-disk format is from a different kernel version, or the
    /// databases are corrupt.
    case chainstateManagerCreationFailed

    public var description: String {
        switch self {
        case .contextCreationFailed:
            return "Kernel context creation failed."
        case .loggingConnectionFailed:
            return "Kernel logging connection creation failed."
        case .transactionCreationFailed:
            return "Transaction creation failed (invalid serialized data)."
        case .blockCreationFailed:
            return "Block creation failed (invalid serialized data)."
        case .blockHeaderCreationFailed:
            return "Block header creation failed (invalid serialized data)."
        case .precomputedDataCreationFailed:
            return "Precomputed transaction data creation failed."
        case .chainstateManagerOptionsCreationFailed:
            return "Chainstate manager options creation failed."
        case .chainstateManagerCreationFailed:
            return "Chainstate manager creation failed."
        }
    }

    public var errorDescription: String? { description }
}
