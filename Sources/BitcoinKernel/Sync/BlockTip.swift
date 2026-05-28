//
//  BlockTip.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// A snapshot identifying a specific block on a chain — paired 32-byte hash,
/// height, and an optional header timestamp. The canonical "where am I?"
/// value used by every ``BlockSource`` conformer and throughout the
/// ``BlockchainSync`` engine.
///
/// Mirrors Bitcoin Core's [`interfaces::BlockTip`](https://github.com/bitcoin/bitcoin/blob/master/src/interfaces/node.h)
/// struct — the same concept surfaced through a Swift value type with
/// synthesized `Equatable` / `Hashable` conformances.
///
/// ```swift
/// let entry = manager.bestEntry
/// let tip = BlockTip(
///     hash: entry.blockHash.data,
///     height: Int(entry.height),
///     timestamp: Date(timeIntervalSince1970: TimeInterval(entry.blockHeader.timestamp))
/// )
/// ```
///
/// - Important: The 32-byte ``hash`` is the canonical block identifier.
///   ``height`` alone is not a safe identifier across reorgs — during a
///   reorg, two different blocks can share the same height. Prefer
///   hash-addressed APIs (``BlockSource/blockHeader(for:)`` and
///   ``BlockSource/block(for:)``) for anything that must survive a reorg.
public struct BlockTip: Sendable, Equatable, Hashable {
    /// The block's identifying hash — always exactly 32 bytes in internal
    /// (kernel) byte order.
    ///
    /// Internal order is the byte-reversed inverse of the display-order hex
    /// shown by block explorers. To render for humans, wrap this in
    /// ``BlockHash`` and read ``BlockHash/description``. The hash is stable
    /// across any chain state that doesn't orphan this specific block, which
    /// is why the whole ``BlockSource`` protocol uses hashes (not heights)
    /// to address blocks.
    public let hash: Data

    /// The block's height above genesis — `0` is the genesis block, matching
    /// Bitcoin Core's [`CChain`](https://github.com/bitcoin/bitcoin/blob/master/src/chain.h)
    /// indexing convention.
    ///
    /// - Warning: Height is **not** a reorg-safe identifier. Two different
    ///   blocks can share the same height while a reorg is in flight. Use
    ///   ``hash`` for chain identity and reserve ``height`` for UI display
    ///   (progress bars, status labels) and for computing
    ///   ``BlockchainSync/Update/verificationProgress``.
    public let height: Int

    /// The block's header timestamp (Unix epoch seconds), or `nil` if the
    /// source did not provide one.
    ///
    /// Remote tips returned from ``EsploraBlockSource/bestTip()`` have
    /// `timestamp == nil` — the tip endpoint only returns height and hash.
    /// Local tips constructed from a kernel ``BlockTreeEntry`` always carry
    /// the timestamp from the stored 80-byte header.
    public let timestamp: Date?

    /// Creates a ``BlockTip``.
    ///
    /// - Parameters:
    ///   - hash: Exactly 32 bytes in internal (kernel) byte order. Passing
    ///     display-order hex bytes here will make the tip compare unequal to
    ///     every kernel-produced tip.
    ///   - height: The block's height above genesis (≥ 0).
    ///   - timestamp: The block's header timestamp, or `nil` when unknown.
    /// - Precondition: `hash.count == 32`. Wrong-length hashes crash rather
    ///   than silently truncate — this is a programmer error, not a runtime
    ///   condition callers can recover from.
    ///
    /// ```swift
    /// BlockTip(hash: Data(repeating: 0, count: 32), height: 0)   // genesis placeholder
    /// ```
    public init(hash: Data, height: Int, timestamp: Date? = nil) {
        precondition(
            hash.count == 32,
            "BlockTip hash must be exactly 32 bytes, got \(hash.count)"
        )
        self.hash = hash
        self.height = height
        self.timestamp = timestamp
    }
}
