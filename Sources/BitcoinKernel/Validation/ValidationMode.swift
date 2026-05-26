//
//  ValidationMode.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Whether a validated block is valid, invalid, or the kernel hit an
/// internal error during validation.
///
/// The high-level verdict carried by ``BlockValidationState/validationMode``.
/// Use ``BlockValidationState/blockValidationResult`` to get the granular
/// reason when this is ``invalid``.
///
/// Maps to `btck_ValidationMode` constants in the kernel C API.
public enum ValidationMode: UInt8, Sendable, CaseIterable, Codable, CustomStringConvertible {
    /// Validation succeeded — the block satisfies consensus rules.
    case valid         = 0

    /// Validation failed — the block was rejected by consensus rules.
    /// Read ``BlockValidationResult`` for the specific reason.
    case invalid       = 1

    /// The kernel encountered an internal error unrelated to the block
    /// itself — typically disk I/O failure, memory pressure, or a bug.
    /// Treat as a system-level problem rather than a block-validity
    /// signal.
    case internalError = 2

    /// A short lowercase label suitable for logs.
    public var description: String {
        switch self {
        case .valid:         return "valid"
        case .invalid:       return "invalid"
        case .internalError: return "internal error"
        }
    }
}
