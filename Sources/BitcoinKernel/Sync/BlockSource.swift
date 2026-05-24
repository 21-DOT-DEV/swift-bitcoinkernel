//
//  BlockSource.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// A source of Bitcoin blockchain data for driving a ``ChainstateManager``.
///
/// Hash-addressed per LDK's [`lightning-block-sync`](https://docs.rs/lightning-block-sync/latest/lightning_block_sync/)
/// convention and Bitcoin Core's own internal `interfaces::Chain` API: every
/// block lookup uses the block's 32-byte hash, not its height. Height lookup
/// (``blockHash(atHeight:)``) is reserved for the one place the sync engine
/// genuinely needs it — computing the fork point when resuming a partially
/// synced chainstate — because height is a reorg hazard everywhere else.
///
/// Conformers deliver blocks via whatever transport they like: HTTP
/// (``EsploraBlockSource``), a bundled test fixture (in-memory mocks), or —
/// in a future phase — a direct Bitcoin P2P peer over `swift-event`. The
/// ``BlockchainSync`` engine treats all conformers identically.
///
/// ### Hash orientation
///
/// All `Data` hashes crossing this protocol are in **internal (kernel) byte
/// order** — matching ``BlockHeader/hash`` and ``Block/hash`` throughout
/// ``BitcoinKernel``. Implementations speaking to external services that use
/// display-order hex (Esplora, most block explorer APIs) are responsible for
/// reversing bytes at the HTTP boundary.
///
/// ### Threading
///
/// Conformers are `Sendable` so they can be shared across tasks and actors.
/// Individual methods are `async` and may suspend on network I/O; conformers
/// should not hold locks across suspension points.
public protocol BlockSource: Sendable {
    /// The source's current best tip — the highest validated block the
    /// source knows.
    ///
    /// Called repeatedly by the sync engine: once at the start of a sync run
    /// (to determine the target), and again each time the local chainstate
    /// reaches the remote tip (to catch source-side growth or reorgs).
    ///
    /// - Returns: A ``BlockTip`` describing the remote best block. The
    ///   returned tip's ``BlockTip/timestamp`` may be `nil` depending on
    ///   what the source can cheaply provide.
    /// - Throws: ``BlockSourceError`` on transport or parse failures.
    func bestTip() async throws -> BlockTip

    /// The hash of the block at the given height, in internal byte order.
    ///
    /// - Parameter height: Height above genesis (0 = genesis).
    /// - Returns: 32 bytes of hash data in internal (kernel) byte order.
    /// - Throws: ``BlockSourceError/notFound`` if the source has no block at
    ///   that height, or a transport-level ``BlockSourceError`` otherwise.
    ///
    /// - Warning: Returns whichever block the source currently thinks is at
    ///   that height. During a reorg, the answer can change. The sync engine
    ///   uses this method exactly once per run — at the fork-point check on
    ///   resume — and walks by hash everywhere else. Don't use it for chain
    ///   identity in application code either.
    func blockHash(atHeight height: Int) async throws -> Data

    /// The 80-byte header of the block with the given hash, parsed through
    /// ``BlockHeader/init(_:)``.
    ///
    /// - Parameter hash: 32-byte block hash in internal byte order.
    /// - Returns: A validated ``BlockHeader`` — the kernel will have already
    ///   checked structure, though not proof-of-work or timestamp context.
    /// - Throws: ``BlockSourceError/notFound`` if the hash is unknown to the
    ///   source; ``BlockSourceError/invalidResponse(_:)`` if the returned
    ///   bytes don't decode cleanly.
    func blockHeader(for hash: Data) async throws -> BlockHeader

    /// The full consensus-serialized block for the given hash.
    ///
    /// - Parameter hash: 32-byte block hash in internal byte order.
    /// - Returns: A ``Block`` ready to pass to
    ///   ``ChainstateManager/processBlock(_:)``.
    /// - Throws: ``BlockSourceError/notFound`` if the hash is unknown;
    ///   ``BlockSourceError/invalidResponse(_:)`` if the body doesn't
    ///   round-trip through the kernel's block parser.
    func block(for hash: Data) async throws -> Block
}
