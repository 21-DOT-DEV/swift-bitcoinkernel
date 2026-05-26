//
//  BlockValidationResult.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// A granular reason why a block failed validation. Paired with
/// ``ValidationMode/invalid`` inside ``BlockValidationState`` to explain a
/// rejection from ``ChainstateManager/processBlockHeader(_:state:)`` or
/// ``ChainstateManager/processBlock(_:)``.
///
/// Maps to `btck_BlockValidationResult` constants in the kernel C API.
/// Case descriptions follow Bitcoin Core's `BlockValidationResult` enum
/// in [`validation_state.h`](https://github.com/bitcoin/bitcoin/blob/master/src/validation.h).
public enum BlockValidationResult: UInt32, Sendable, CaseIterable, Codable, CustomStringConvertible {
    /// The state carries no rejection — either validation succeeded or
    /// the state has not yet been populated.
    case unset          = 0

    /// Rejected by Bitcoin's consensus rules — script execution,
    /// coin-value balance, or other `ConnectBlock`-level checks failed.
    case consensus      = 1

    /// The kernel has seen this block before and cached it as invalid
    /// without retaining the specific reason. Retry is pointless.
    case cachedInvalid  = 2

    /// Invalid at the header level — proof-of-work below target,
    /// timestamp not greater than MTP, or malformed header structure.
    case invalidHeader  = 3

    /// Block contents don't match the commitments in the header
    /// (merkle root mismatch, witness commitment mismatch). Typically a
    /// corruption or malicious-peer signal rather than a legitimate
    /// validity failure.
    case mutated        = 4

    /// The block's previous-block hash doesn't match any block the
    /// kernel knows about. Provide the parent via
    /// ``ChainstateManager/processBlock(_:)`` first.
    case missingPrev    = 5

    /// An ancestor of this block has already been rejected as invalid,
    /// so this block is rejected transitively without running full
    /// validation.
    case invalidPrev    = 6

    /// Block timestamp is more than 2 hours ahead of the node's
    /// network-adjusted time — the kernel refuses to accept clearly
    /// future-dated blocks.
    case timeFuture     = 7

    /// The header chain the block would extend has cumulatively
    /// insufficient proof-of-work (below the minimum chain work
    /// checkpoint). The kernel won't spend resources validating blocks
    /// on such chains.
    case headerLowWork  = 8

    public var description: String {
        switch self {
        case .unset:         return "unset"
        case .consensus:     return "consensus"
        case .cachedInvalid: return "cached invalid"
        case .invalidHeader: return "invalid header"
        case .mutated:       return "mutated"
        case .missingPrev:   return "missing previous block"
        case .invalidPrev:   return "invalid previous block"
        case .timeFuture:    return "time too far in future"
        case .headerLowWork: return "header low work"
        }
    }
}
