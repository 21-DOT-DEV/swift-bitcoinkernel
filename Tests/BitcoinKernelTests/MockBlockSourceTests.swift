//
//  MockBlockSourceTests.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
import BitcoinKernel
import Foundation

// MARK: - MockBlockSource sanity tests
//
// `MockBlockSource` is a test-support type in
// `Tests/BitcoinKernelTests/Support/MockBlockSource.swift`. These tests give
// it enough coverage that downstream `BlockchainSync` tests can trust its
// behavior. We verify the API surface used by Cycle A2.2 tests:
//   - Configure and update `bestTip`.
//   - Register a block by height and look up its hash / header / raw block.
//   - Inject scripted errors on specific methods.

@Test func mockBlockSourceReturnsConfiguredBestTip() async throws {
    let tip = BlockTip(hash: Data(repeating: 0xAB, count: 32), height: 100)
    let mock = MockBlockSource(bestTip: tip)
    let result = try await mock.bestTip()
    #expect(result == tip)
}

@Test func mockBlockSourceUpdatesBestTipWhenSet() async throws {
    let initialTip = BlockTip(hash: Data(repeating: 0xAB, count: 32), height: 100)
    let newTip = BlockTip(hash: Data(repeating: 0xCD, count: 32), height: 200)
    let mock = MockBlockSource(bestTip: initialTip)
    mock.setBestTip(newTip)
    let result = try await mock.bestTip()
    #expect(result == newTip)
}

@Test func mockBlockSourceBlockHashAtKnownHeightRoundTrips() async throws {
    let tip = BlockTip(hash: Data(repeating: 0, count: 32), height: 0)
    let mock = MockBlockSource(bestTip: tip)
    let hash = Data(repeating: 0xCD, count: 32)
    mock.registerBlockHash(hash, atHeight: 5)
    let result = try await mock.blockHash(atHeight: 5)
    #expect(result == hash)
}

@Test func mockBlockSourceBlockHashAtUnknownHeightThrowsNotFound() async {
    let tip = BlockTip(hash: Data(repeating: 0, count: 32), height: 0)
    let mock = MockBlockSource(bestTip: tip)
    do {
        _ = try await mock.blockHash(atHeight: 999)
        Issue.record("expected throw")
    } catch let error as BlockSourceError {
        if case .notFound = error { /* ok */ } else {
            Issue.record("expected .notFound, got \(error)")
        }
    } catch {
        Issue.record("expected BlockSourceError, got \(error)")
    }
}

@Test func mockBlockSourceScriptedBestTipErrorThrows() async {
    let tip = BlockTip(hash: Data(repeating: 0, count: 32), height: 0)
    let mock = MockBlockSource(bestTip: tip)
    mock.setNextBestTipError(.network(underlying: URLError(.timedOut)))

    await #expect(throws: BlockSourceError.self) {
        _ = try await mock.bestTip()
    }
    // Subsequent calls revert to the configured bestTip (error is one-shot).
    let recovered = try? await mock.bestTip()
    #expect(recovered == tip)
}
