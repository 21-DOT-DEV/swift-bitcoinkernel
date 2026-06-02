//
//  BlockchainSyncEngineTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

// Depends on `RegtestChainBuilder`, which is gated on CryptoKit. See the
// note in `Support/RegtestChainBuilder.swift` and `roadmap.md`
// "Linux Test Coverage".
#if canImport(CryptoKit)

import Testing
import BitcoinKernel
import Foundation

// MARK: - Helpers

/// Spin up a fresh in-memory regtest chainstate for a test.
@MainActor
private func makeRegtestKernel() throws -> (Context, ChainstateManager, URL) {
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

    let params = ChainParameters(.regtest)
    let ctxOpts = ContextOptions()
    ctxOpts.setChainParams(params)
    let context = try Context(options: ctxOpts)

    let options = try ChainstateManagerOptions(context: context, dataDirectory: tmpDir.path)
    options.setBlockTreeDBInMemory(true)
    options.setChainstateDBInMemory(true)
    let manager = try ChainstateManager(options: options)
    return (context, manager, tmpDir)
}

/// Populate a MockBlockSource with a mined regtest chain.
private func registerChain(
    _ chain: [RegtestChainBuilder.MinedBlock],
    in mock: MockBlockSource
) throws {
    for mined in chain {
        let header = try BlockHeader(mined.headerBytes)
        let block = try Block(mined.blockBytes)
        mock.registerBlock(
            block,
            header: header,
            hash: mined.hash,
            atHeight: mined.height
        )
    }
}

// MARK: - Happy-path sync

@Test(.kernelSerialized) func syncFromGenesisToSyntheticChain() async throws {
    let (context, manager, tmpDir) = try await MainActor.run { try makeRegtestKernel() }
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let genesisHash = manager.bestEntry.blockHash.data
    let chain = RegtestChainBuilder.mineChain(count: 5, previousHash: genesisHash)

    let mock = MockBlockSource(bestTip: BlockTip(hash: chain.last!.hash, height: 5))
    try registerChain(chain, in: mock)

    let sync = BlockchainSync(manager: manager, source: mock, context: context)

    var updates: [BlockchainSync.Update] = []
    for await update in sync.updates() {
        updates.append(update)
    }

    // preparing + 5× syncing + finished = 7 updates.
    #expect(updates.count == 7, "got \(updates.count) updates")
    #expect(updates.first?.state == .preparing)
    #expect(updates.last?.state == .finished)
    #expect(updates.last?.tip.height == 5)
    #expect(manager.bestEntry.height == 5)

    for i in 1...5 {
        #expect(updates[i].state == .syncing)
        #expect(updates[i].tip.height == i)
    }
}

@Test(.kernelSerialized) func syncFinishesImmediatelyWhenAlreadyAtRemoteTip() async throws {
    let (context, manager, tmpDir) = try await MainActor.run { try makeRegtestKernel() }
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    // Local and remote both at genesis (height 0).
    let genesisHash = manager.bestEntry.blockHash.data
    let mock = MockBlockSource(bestTip: BlockTip(hash: genesisHash, height: 0))

    let sync = BlockchainSync(manager: manager, source: mock, context: context)

    var updates: [BlockchainSync.Update] = []
    for await update in sync.updates() {
        updates.append(update)
    }

    // preparing + finished only; no syncing updates.
    #expect(updates.count == 2, "got \(updates.count) updates")
    #expect(updates.first?.state == .preparing)
    #expect(updates.last?.state == .finished)
    #expect(updates.allSatisfy { $0.state != .syncing })
    #expect(manager.bestEntry.height == 0)
}

// MARK: - Fork-point failure

@Test(.kernelSerialized) func syncFailsOnForkAtResumeHeight() async throws {
    let (context, manager, tmpDir) = try await MainActor.run { try makeRegtestKernel() }
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    // Pre-sync 3 blocks into local chainstate.
    let genesisHash = manager.bestEntry.blockHash.data
    let localChain = RegtestChainBuilder.mineChain(count: 3, previousHash: genesisHash)
    for mined in localChain {
        let block = try Block(mined.blockBytes)
        let (ok, _) = manager.processBlock(block)
        #expect(ok)
    }
    #expect(manager.bestEntry.height == 3)

    // Remote claims a DIFFERENT hash at height 3 — a different chain.
    let mock = MockBlockSource(
        bestTip: BlockTip(hash: Data(repeating: 0xEE, count: 32), height: 5)
    )
    mock.registerBlockHash(Data(repeating: 0xFF, count: 32), atHeight: 3)

    let sync = BlockchainSync(manager: manager, source: mock, context: context)

    var updates: [BlockchainSync.Update] = []
    for await update in sync.updates() {
        updates.append(update)
    }

    #expect(updates.count >= 2)
    #expect(updates.first?.state == .preparing)
    guard case .failed(let reason)? = updates.last?.state else {
        Issue.record("expected final state .failed, got \(String(describing: updates.last?.state))")
        return
    }
    #expect(reason.lowercased().contains("diverg") || reason.lowercased().contains("fork"),
            "failure reason should mention divergence; got '\(reason)'")
}

// MARK: - Cancellation

@Test(.kernelSerialized) func cancellationEndsSequenceSilently() async throws {
    let (context, manager, tmpDir) = try await MainActor.run { try makeRegtestKernel() }
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let genesisHash = manager.bestEntry.blockHash.data
    let chain = RegtestChainBuilder.mineChain(count: 20, previousHash: genesisHash)

    let mock = MockBlockSource(bestTip: BlockTip(hash: chain.last!.hash, height: 20))
    try registerChain(chain, in: mock)

    let sync = BlockchainSync(manager: manager, source: mock, context: context)

    let task = Task {
        var updates: [BlockchainSync.Update] = []
        for await update in sync.updates() {
            updates.append(update)
            // Stop consuming after 3 syncing updates to simulate user cancel.
            if update.state == .syncing, update.tip.height == 3 {
                break
            }
        }
        return updates
    }
    let updates = await task.value

    // Should see preparing + a few syncing updates, but NO terminal .failed /
    // .finished — consumer cancelled before sync completed.
    #expect(updates.count >= 2)
    #expect(updates.first?.state == .preparing)
    #expect(!updates.contains(where: {
        if case .failed = $0.state { return true }
        return false
    }), "cancel must not emit .failed")
    // Not finished either (broke out early).
    #expect(updates.last?.state != .finished)
    // Chainstate should have advanced at least partway but not past 20.
    #expect(manager.bestEntry.height >= 1)
    #expect(manager.bestEntry.height <= 20)
}

// MARK: - Progress semantics

@Test(.kernelSerialized) func verificationProgressMonotonicallyIncreases() async throws {
    let (context, manager, tmpDir) = try await MainActor.run { try makeRegtestKernel() }
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let genesisHash = manager.bestEntry.blockHash.data
    let chain = RegtestChainBuilder.mineChain(count: 5, previousHash: genesisHash)

    let mock = MockBlockSource(bestTip: BlockTip(hash: chain.last!.hash, height: 5))
    try registerChain(chain, in: mock)

    let sync = BlockchainSync(manager: manager, source: mock, context: context)

    var progresses: [Double] = []
    for await update in sync.updates() {
        progresses.append(update.verificationProgress)
    }

    for i in 1..<progresses.count {
        #expect(progresses[i] >= progresses[i - 1],
                "progress should be monotonically non-decreasing; index \(i-1)→\(i): \(progresses[i-1]) → \(progresses[i])")
    }
    #expect(progresses.last == 1.0)
}

@Test(.kernelSerialized) func foundationProgressReflectsCompletion() async throws {
    let (context, manager, tmpDir) = try await MainActor.run { try makeRegtestKernel() }
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let genesisHash = manager.bestEntry.blockHash.data
    let chain = RegtestChainBuilder.mineChain(count: 5, previousHash: genesisHash)

    let mock = MockBlockSource(bestTip: BlockTip(hash: chain.last!.hash, height: 5))
    try registerChain(chain, in: mock)

    let sync = BlockchainSync(manager: manager, source: mock, context: context)

    // Drain the sequence.
    for await _ in sync.updates() {}

    // After .finished, Foundation.Progress should report full completion.
    #expect(sync.progress.totalUnitCount == 5)
    #expect(sync.progress.completedUnitCount == 5)
    #expect(sync.progress.fractionCompleted == 1.0)
}

// MARK: - Growing remote tip

@Test(.kernelSerialized) func growingRemoteTipExtendsTotalUnitCount() async throws {
    let (context, manager, tmpDir) = try await MainActor.run { try makeRegtestKernel() }
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let genesisHash = manager.bestEntry.blockHash.data
    // Pre-mine 10 blocks; register all in mock so fetches succeed, but start
    // bestTip at height 5 and bump to 10 mid-sync.
    let chain = RegtestChainBuilder.mineChain(count: 10, previousHash: genesisHash)

    let mock = MockBlockSource(bestTip: BlockTip(hash: chain[4].hash, height: 5))
    try registerChain(chain, in: mock)

    // Bump the remote tip the moment the engine fetches block #3, ensuring
    // the bump is visible to the engine's re-poll at height 5 regardless
    // of consumer iteration timing.
    let bumpHash = chain[2].hash
    let newTip = BlockTip(hash: chain.last!.hash, height: 10)
    mock.setOnBlockFetched { [mock] hash in
        if hash == bumpHash {
            mock.setBestTip(newTip)
        }
    }

    let sync = BlockchainSync(manager: manager, source: mock, context: context)

    var updates: [BlockchainSync.Update] = []
    for await update in sync.updates() {
        updates.append(update)
    }

    #expect(updates.last?.state == .finished)
    #expect(updates.last?.tip.height == 10)
    #expect(updates.last?.remoteTip.height == 10)
    #expect(manager.bestEntry.height == 10)
    #expect(sync.progress.totalUnitCount == 10)
    #expect(sync.progress.completedUnitCount == 10)
}

// MARK: - BlockSource failure → .failed state

@Test(.kernelSerialized) func blockSourceFailureBecomesFailedState() async throws {
    let (context, manager, tmpDir) = try await MainActor.run { try makeRegtestKernel() }
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let genesisHash = manager.bestEntry.blockHash.data
    let mock = MockBlockSource(bestTip: BlockTip(hash: genesisHash, height: 0))
    // First bestTip call throws; source is uncooperative.
    mock.setNextBestTipError(.network(underlying: URLError(.timedOut)))

    let sync = BlockchainSync(manager: manager, source: mock, context: context)

    var updates: [BlockchainSync.Update] = []
    for await update in sync.updates() {
        updates.append(update)
    }

    #expect(updates.count >= 2)
    #expect(updates.first?.state == .preparing)
    guard case .failed(let reason)? = updates.last?.state else {
        Issue.record("expected final state .failed, got \(String(describing: updates.last?.state))")
        return
    }
    #expect(!reason.isEmpty, "failure reason should be informative")
}

#endif // canImport(CryptoKit)
