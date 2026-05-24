//
//  BlockHeader.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

internal import libbitcoinkernel
import Foundation

/// A Bitcoin block header — exactly 80 bytes holding the six fields that
/// make up the proof-of-work commitment: `version (4) | prev hash (32) |
/// merkle root (32) | time (4) | nBits (4) | nonce (4)`.
///
/// Headers are what miners iterate (changing the `nonce` until the
/// resulting hash is ≤ the target implied by `bits`) and what the P2P
/// network gossips before blocks. Use for header-first IBD and for
/// lightweight chain-presence checks that don't need full transaction
/// data.
///
/// Wraps the opaque `btck_BlockHeader` type; `deinit` calls
/// `btck_block_header_destroy` when the last Swift reference drops.
public final class BlockHeader: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Parses a block header from its 80-byte serialized form.
    ///
    /// The input must be exactly 80 bytes in the standard header layout.
    /// Parsing checks only that the data is structurally a header — no
    /// proof-of-work check, no linkage check. Those happen in
    /// ``ChainstateManager/processBlockHeader(_:state:)``.
    ///
    /// - Parameter data: Exactly 80 bytes of serialized header data.
    /// - Throws: ``KernelError/blockHeaderCreationFailed`` when the input
    ///   is not exactly 80 bytes or otherwise fails to parse.
    public init(_ data: Data) throws {
        guard let ptr = data.withUnsafeBytes({ rawBuf -> OpaquePointer? in
            guard let baseAddress = rawBuf.baseAddress else { return nil }
            return btck_block_header_create(baseAddress, rawBuf.count)
        }) else {
            throw KernelError.blockHeaderCreationFailed
        }
        self.pointer = ptr
    }

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The block's hash — double-SHA256 of these 80 header bytes.
    ///
    /// Returns an owned copy in internal (kernel) byte order. Reverse for
    /// display-order hex.
    public var hash: BlockHash {
        BlockHash(pointer: btck_block_header_get_hash(pointer))
    }

    /// The hash of the previous block's header — the chain linkage field.
    ///
    /// Genesis blocks have all-zero previous-hash. Returns an owned copy
    /// in internal (kernel) byte order.
    public var previousHash: BlockHash {
        let viewPtr = btck_block_header_get_prev_hash(pointer)
        return BlockHash(pointer: btck_block_hash_copy(viewPtr))
    }

    /// The block's timestamp in Unix epoch seconds as claimed by the miner.
    ///
    /// Consensus requires this to be greater than the median of the
    /// previous 11 block timestamps (MTP rule) and no more than 2 hours in
    /// the future relative to network-adjusted time. Not strictly
    /// monotonic across blocks.
    public var timestamp: UInt32 {
        btck_block_header_get_timestamp(pointer)
    }

    /// The difficulty target in compact (`nBits`) encoding — the
    /// threshold the block's hash must meet or fall below for the
    /// proof-of-work to be valid.
    ///
    /// Decodes per Bitcoin Core's
    /// [`arith_uint256::SetCompact`](https://github.com/bitcoin/bitcoin/blob/master/src/arith_uint256.cpp):
    /// top byte = exponent, low 23 bits = mantissa; the full 256-bit
    /// target is `mantissa << 8*(exponent-3)`.
    public var bits: UInt32 {
        btck_block_header_get_bits(pointer)
    }

    /// The block version field. Interpreted per
    /// [BIP 9](https://github.com/bitcoin/bips/blob/master/bip-0009.mediawiki)
    /// for signalling soft-fork readiness; must be ≥ 4 on networks where
    /// BIP 65 is active (all current Bitcoin networks).
    public var version: Int32 {
        btck_block_header_get_version(pointer)
    }

    /// The nonce — the `UInt32` that miners increment to find a header
    /// whose hash satisfies ``bits``. Exhaustively searched during
    /// mining; meaningless except as part of the proof-of-work commitment.
    public var nonce: UInt32 {
        btck_block_header_get_nonce(pointer)
    }

    deinit {
        btck_block_header_destroy(pointer)
    }
}
