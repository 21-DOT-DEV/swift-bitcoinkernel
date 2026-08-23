//
//  BlockchainSyncTeardownTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

// Deliberately NOT gated on CryptoKit. The sibling
// `BlockchainSyncEngineTests.swift` is, because its fixtures mine synthetic
// blocks via `RegtestChainBuilder` (CryptoKit-only until the swift-crypto
// dependency lands — see `roadmap.md` "Linux Test Coverage"). Nothing here
// needs that, and the bug guarded below is a pure Swift-concurrency ordering
// problem with no platform component, so it runs everywhere.

import Testing
import BitcoinKernel
import Foundation
// Explicit on Linux, implicit on Apple platforms. `ParkingBlockSource` needs it
// for a delay that ignores task cancellation.
import Dispatch

/// A ``BlockSource`` that parks inside `bestTip()` in a delay which ignores
/// task cancellation.
///
/// This models the production hazard faithfully. In a real sync the producer
/// stalls inside `ChainstateManager.processBlock`, a synchronous C call that
/// Swift's cooperative cancellation cannot interrupt — which is exactly why
/// ``Context/interrupt()`` exists. A `Task.sleep` would be useless here: it
/// unwinds the instant it is cancelled, closing the very window this test
/// needs held open.
///
/// `bestTip()` is the park point because ``runSyncLoop`` yields `.preparing`
/// and then calls it with no cancellation checkpoint in between. The producer
/// is therefore guaranteed to be inside it, and un-cancellable, at the moment
/// the consumer below stops iterating.
private final class ParkingBlockSource: BlockSource, @unchecked Sendable {
    private let wrapped: MockBlockSource
    private let parkSeconds: Double

    init(wrapping wrapped: MockBlockSource, parkSeconds: Double) {
        self.wrapped = wrapped
        self.parkSeconds = parkSeconds
    }

    func bestTip() async throws -> BlockTip {
        await withUnsafeContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + parkSeconds) {
                continuation.resume()
            }
        }
        return try await wrapped.bestTip()
    }

    func blockHash(atHeight height: Int) async throws -> Data {
        try await wrapped.blockHash(atHeight: height)
    }

    func blockHeader(for hash: Data) async throws -> BlockHeader {
        try await wrapped.blockHeader(for: hash)
    }

    func block(for hash: Data) async throws -> Block {
        try await wrapped.block(for: hash)
    }
}

/// Regression test for the reindex reopen race.
///
/// `AsyncStream.onTermination` only *requests* that the sync producer stop.
/// Until it actually unwinds, the producer strongly holds the
/// ``ChainstateManager`` and with it the LevelDB lock on the data directory.
/// A reindex stops the sync and immediately reopens that same directory, so
/// before ``BlockchainSync/shutdown()`` existed the reopen could land while the
/// previous databases were still open and fail with
/// ``KernelError/chainstateManagerCreationFailed``.
///
/// It surfaced as an intermittent KernelApp iOS CI failure
/// (`requestReindex(.chainstate)`, run 32344108476) rather than a reproducible
/// local one. Two details make this version deterministic in both directions:
///
/// - **On-disk databases.** The lock being guarded is a real file lock in the
///   data directory; in-memory databases never take one, which is why the rest
///   of this file's fixtures cannot catch this.
/// - **A non-cancellable park.** ``ParkingBlockSource`` guarantees the producer
///   is provably still alive when the reopen is attempted. Remove the
///   `await sync.shutdown()` line below and this test fails every time.
@Test(.kernelSerialized) func shutdownReleasesDataDirectoryBeforeReopen() async throws {
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    /// Open on disk at `tmpDir`. Deliberately NOT the in-memory helper above.
    @MainActor
    func openOnDisk() throws -> (Context, ChainstateManager) {
        let ctxOpts = ContextOptions()
        ctxOpts.setChainParams(ChainParameters(.regtest))
        let context = try Context(options: ctxOpts)
        let options = try ChainstateManagerOptions(context: context, dataDirectory: tmpDir.path)
        let manager = try ChainstateManager(options: options)
        return (context, manager)
    }

    // Scoped to a nested function so every reference it creates is released
    // when it returns, leaving `shutdown()` as the only thing that can account
    // for the producer letting go of the databases.
    func firstRun() async throws {
        let (context, manager) = try await MainActor.run { try openOnDisk() }
        let mock = MockBlockSource(bestTip: BlockTip(hash: Data(repeating: 0xAA, count: 32), height: 1))
        let parking = ParkingBlockSource(wrapping: mock, parkSeconds: 0.5)
        let sync = BlockchainSync(manager: manager, source: parking, context: context)

        // Take the first update (.preparing) and stop, mirroring a reindex
        // tearing the run down mid-flight. The producer is now parked in
        // `bestTip()` and cannot observe its own cancellation.
        let consumer = Task {
            for await _ in sync.updates() { break }
        }
        await consumer.value

        // The barrier under test.
        await sync.shutdown()
    }
    try await firstRun()

    // Reopening the SAME directory must succeed.
    let (_, reopened) = try await MainActor.run { try openOnDisk() }
    #expect(reopened.bestEntry.height == 0, "reopened regtest chainstate sits at genesis")
}
