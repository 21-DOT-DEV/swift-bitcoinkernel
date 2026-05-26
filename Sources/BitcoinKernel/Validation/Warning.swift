//
//  Warning.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Warnings surfaced by validation via
/// ``NotificationCallbacks/warningSet`` and cleared via
/// ``NotificationCallbacks/warningUnset``.
///
/// Warnings represent operationally significant conditions that don't
/// block validation but should be surfaced to operators — typically
/// shown in a UI banner or emergency-logged.
///
/// Maps to `btck_Warning` constants in the kernel C API.
public enum Warning: UInt8, Sendable, CaseIterable, Codable, CustomStringConvertible {
    /// Unknown new consensus rules may have been activated — version-bit
    /// signalling indicates a soft fork this kernel version doesn't
    /// understand. Strong hint to upgrade the kernel (and by extension,
    /// this package).
    case unknownNewRulesActivated = 0

    /// A competing chain with substantial proof-of-work but containing
    /// an invalid block has been detected. Usually indicates an attack
    /// or a peer running non-consensus code; review network peer list.
    case largeWorkInvalidChain    = 1

    /// A short human-readable label suitable for UI banners.
    public var description: String {
        switch self {
        case .unknownNewRulesActivated: return "unknown new rules activated"
        case .largeWorkInvalidChain:    return "large-work invalid chain detected"
        }
    }
}
