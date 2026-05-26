//
//  MockBlockSource.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2022-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

//  Test-only ``BlockSource`` for KernelApp view-model tests.

import BitcoinKernel
import Foundation

/// Scriptable ``BlockSource`` for KernelApp tests. Mirrors the structure of
/// the canonical mock in `Tests/BitcoinKernelTests/Support/MockBlockSource.swift`
/// — duplicated rather than imported because KernelAppTests is a Tuist
/// target that cannot depend on `BitcoinKernelTests` SPM-internal sources.
///
/// Lets view-model tests drive deterministic remote chains without HTTP.
final class MockBlockSource: BlockSource, @unchecked Sendable {
    private let lock = NSLock()
    private var state: State

    private struct State {
        var bestTip: BlockTip
        var hashesByHeight: [Int: Data] = [:]
        var headersByHash: [Data: BlockHeader] = [:]
        var blocksByHash: [Data: Block] = [:]

        var nextBestTipError: BlockSourceError?
        var nextBlockHashErrorsByHeight: [Int: BlockSourceError] = [:]
        var nextBlockErrorsByHash: [Data: BlockSourceError] = [:]

        /// When `true`, `bestTip()` hangs (cancellation-aware) so the
        /// caller can drive a stop-mid-sync test deterministically.
        var freezeBestTip: Bool = false
    }

    init(bestTip: BlockTip) {
        self.state = State(bestTip: bestTip)
    }

    // MARK: - Test-side mutation

    func setBestTip(_ tip: BlockTip) {
        lock.withLock { state.bestTip = tip }
    }

    func registerBlockHash(_ hash: Data, atHeight height: Int) {
        lock.withLock { state.hashesByHeight[height] = hash }
    }

    func registerBlockHeader(_ header: BlockHeader, forHash hash: Data) {
        lock.withLock { state.headersByHash[hash] = header }
    }

    func registerBlock(_ block: Block, forHash hash: Data) {
        lock.withLock { state.blocksByHash[hash] = block }
    }

    func registerBlock(_ block: Block, header: BlockHeader, hash: Data, atHeight height: Int) {
        lock.withLock {
            state.hashesByHeight[height] = hash
            state.headersByHash[hash] = header
            state.blocksByHash[hash] = block
        }
    }

    func setNextBestTipError(_ error: BlockSourceError) {
        lock.withLock { state.nextBestTipError = error }
    }

    func setNextBlockHashError(_ error: BlockSourceError, atHeight height: Int) {
        lock.withLock { state.nextBlockHashErrorsByHeight[height] = error }
    }

    func setNextBlockError(_ error: BlockSourceError, forHash hash: Data) {
        lock.withLock { state.nextBlockErrorsByHash[hash] = error }
    }

    /// Make `bestTip()` hang until the caller's `Task` is cancelled. Used
    /// to drive stop-mid-sync tests deterministically without racing.
    func freezeBestTip() {
        lock.withLock { state.freezeBestTip = true }
    }

    // MARK: - BlockSource conformance

    func bestTip() async throws -> BlockTip {
        let (tip, error, frozen): (BlockTip, BlockSourceError?, Bool) = lock.withLock {
            defer { state.nextBestTipError = nil }
            return (state.bestTip, state.nextBestTipError, state.freezeBestTip)
        }
        if frozen {
            // Cancellation-aware sleep — Task.cancel propagates a
            // CancellationError that BlockchainSync's loop treats as a
            // clean termination (no .failed emission).
            try await Task.sleep(for: .seconds(3600))
        }
        if let error { throw error }
        return tip
    }

    func blockHash(atHeight height: Int) async throws -> Data {
        let resolved: Result<Data, BlockSourceError> = lock.withLock {
            if let error = state.nextBlockHashErrorsByHeight.removeValue(forKey: height) {
                return .failure(error)
            }
            if let hash = state.hashesByHeight[height] {
                return .success(hash)
            }
            return .failure(.notFound)
        }
        return try resolved.get()
    }

    func blockHeader(for hash: Data) async throws -> BlockHeader {
        let resolved: Result<BlockHeader, BlockSourceError> = lock.withLock {
            if let header = state.headersByHash[hash] {
                return .success(header)
            }
            return .failure(.notFound)
        }
        return try resolved.get()
    }

    func block(for hash: Data) async throws -> Block {
        let resolved: Result<Block, BlockSourceError> = lock.withLock {
            if let error = state.nextBlockErrorsByHash.removeValue(forKey: hash) {
                return .failure(error)
            }
            if let block = state.blocksByHash[hash] {
                return .success(block)
            }
            return .failure(.notFound)
        }
        return try resolved.get()
    }
}
