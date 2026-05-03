import Foundation
import BitcoinKernel

/// A scriptable ``BlockSource`` for unit tests. Not public — lives in the
/// test target only. Lets `BlockchainSync` tests drive a deterministic
/// "remote chain" without real HTTP.
///
/// ### Usage
///
/// ```swift
/// let mock = MockBlockSource(bestTip: BlockTip(hash: h0, height: 0))
/// mock.registerBlockHash(h1, atHeight: 1)
/// mock.registerBlock(block1, header: header1, atHeight: 1)
/// mock.setBestTip(BlockTip(hash: h1, height: 1))
/// ```
///
/// ### Error injection
///
/// `setNextBestTipError(_:)`, `setNextBlockHashError(_:atHeight:)`,
/// `setNextBlockError(_:forHash:)` stage a one-shot error that is consumed
/// by the next matching call. Lets tests drive `.failed` states without
/// complex branching in production code.
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

    /// Convenience: register a height→hash mapping plus header and block
    /// bodies in one call.
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

    // MARK: - BlockSource conformance

    func bestTip() async throws -> BlockTip {
        let (tip, error): (BlockTip, BlockSourceError?) = lock.withLock {
            defer { state.nextBestTipError = nil }
            return (state.bestTip, state.nextBestTipError)
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
