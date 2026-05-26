//
//  RegtestChainBuilderTests.swift
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

// MARK: - RegtestChainBuilder sanity tests
//
// These tests prove the miner produces blocks that pass real kernel
// consensus validation. If they go green, Cycle A2.2 integration tests
// can rely on synthetic chains.

@Test func regtestChainBuilderProducesKernelAcceptedSingleBlock() throws {
    let params = ChainParameters(.regtest)
    let ctxOpts = ContextOptions()
    ctxOpts.setChainParams(params)
    let context = try Context(options: ctxOpts)

    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).path
    defer { try? FileManager.default.removeItem(atPath: tmpDir) }
    let options = try ChainstateManagerOptions(context: context, dataDirectory: tmpDir)
    options.setBlockTreeDBInMemory(true)
    options.setChainstateDBInMemory(true)

    let manager = try ChainstateManager(options: options)
    let genesisHash = manager.bestEntry.blockHash.data

    let chain = RegtestChainBuilder.mineChain(
        count: 1,
        startingAt: 1,
        previousHash: genesisHash
    )
    #expect(chain.count == 1)

    let block = try Block(chain[0].blockBytes)
    // Round-trip check: the Block parsed by the kernel should match what we mined.
    #expect(block.data == chain[0].blockBytes, "Block serialization round-trips")
    #expect(block.hash.data == chain[0].hash, "Block hash matches mined hash")

    let (success, isNew) = manager.processBlock(block)
    #expect(success, "processBlock rejected the synthetic regtest block")
    #expect(isNew, "synthetic block should be new to the chainstate")
    #expect(manager.bestEntry.height == 1)
}

@Test func regtestChainBuilderProducesFiveLinkedBlocks() throws {
    let params = ChainParameters(.regtest)
    let ctxOpts = ContextOptions()
    ctxOpts.setChainParams(params)
    let context = try Context(options: ctxOpts)

    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).path
    defer { try? FileManager.default.removeItem(atPath: tmpDir) }
    let options = try ChainstateManagerOptions(context: context, dataDirectory: tmpDir)
    options.setBlockTreeDBInMemory(true)
    options.setChainstateDBInMemory(true)

    let manager = try ChainstateManager(options: options)
    let genesisHash = manager.bestEntry.blockHash.data

    let chain = RegtestChainBuilder.mineChain(
        count: 5,
        startingAt: 1,
        previousHash: genesisHash
    )
    #expect(chain.count == 5)

    for (index, mined) in chain.enumerated() {
        #expect(mined.height == index + 1)
        let block = try Block(mined.blockBytes)
        let (success, isNew) = manager.processBlock(block)
        #expect(success, "processBlock rejected synthetic block at height \(mined.height)")
        #expect(isNew, "synthetic block at height \(mined.height) was not new")
    }

    #expect(manager.bestEntry.height == 5)
    // Final tip's hash should equal the last mined block's hash.
    #expect(manager.bestEntry.blockHash.data == chain.last?.hash)
}

@Test func regtestChainBuilderSubsidyMatchesBitcoinCore() {
    // Regtest starts at 50 BTC, halves every 150 blocks.
    #expect(RegtestChainBuilder.subsidy(atHeight: 0) == 5_000_000_000)
    #expect(RegtestChainBuilder.subsidy(atHeight: 1) == 5_000_000_000)
    #expect(RegtestChainBuilder.subsidy(atHeight: 149) == 5_000_000_000)
    #expect(RegtestChainBuilder.subsidy(atHeight: 150) == 2_500_000_000)
    #expect(RegtestChainBuilder.subsidy(atHeight: 300) == 1_250_000_000)
}

#endif // canImport(CryptoKit)
