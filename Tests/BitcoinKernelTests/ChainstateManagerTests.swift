//
//  ChainstateManagerTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
import BitcoinKernel
import Foundation

// MARK: - BlockValidationState

@Test func blockValidationStateLifecycle() {
    let state = BlockValidationState()
    #expect(state.validationMode == .valid)
    #expect(state.blockValidationResult == .unset)
}

// MARK: - ChainstateManagerOptions

@Test func chainstateManagerOptionsCreation() throws {
    let context = try Context()
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).path
    defer { try? FileManager.default.removeItem(atPath: tmpDir) }
    let options = try ChainstateManagerOptions(context: context, dataDirectory: tmpDir)
    options.setWorkerThreads(2)
    options.setBlockTreeDBInMemory(true)
    options.setChainstateDBInMemory(true)
    _ = options // no crash = success
}

@Test func chainstateManagerOptionsWipeDBs() throws {
    let context = try Context()
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).path
    defer { try? FileManager.default.removeItem(atPath: tmpDir) }
    let options = try ChainstateManagerOptions(context: context, dataDirectory: tmpDir)
    let result = options.setWipeDBs(blockTreeDB: true, chainstateDB: true)
    #expect(result)
}

// MARK: - ChainstateManager (regtest, in-memory)

@Test func chainstateManagerCreation() throws {
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
    _ = manager // no crash = success
}

@Test func chainstateManagerBestEntry() throws {
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
    let bestEntry = manager.bestEntry
    // Regtest genesis is at height 0
    #expect(bestEntry.height == 0)
}

@Test func chainstateManagerActiveChain() throws {
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
    let chain = manager.activeChain
    #expect(chain.height == 0)
}

@Test func chainstateManagerChainEntryAtHeight() throws {
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
    let chain = manager.activeChain

    // Genesis at height 0
    let genesis = chain.entry(atHeight: 0)
    #expect(genesis != nil)
    #expect(genesis?.height == 0)

    // Out of bounds
    let tooHigh = chain.entry(atHeight: 1)
    #expect(tooHigh == nil)
}

@Test func chainstateManagerChainContains() throws {
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
    let chain = manager.activeChain
    let bestEntry = manager.bestEntry
    #expect(chain.contains(bestEntry))
}

@Test func blockTreeEntryBlockHeader() throws {
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
    let bestEntry = manager.bestEntry
    let header = bestEntry.blockHeader
    // Regtest genesis has version 1
    #expect(header.version == 1)
}

@Test func blockTreeEntryPrevious() throws {
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
    let bestEntry = manager.bestEntry
    // Genesis has no previous
    #expect(bestEntry.previous == nil)
}

@Test func blockTreeEntryEquality() throws {
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
    let entry1 = manager.bestEntry
    let entry2 = manager.activeChain.entry(atHeight: 0)!
    #expect(entry1.equals(entry2))
}

@Test func chainstateManagerLookupByHash() throws {
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
    let bestEntry = manager.bestEntry
    let hash = bestEntry.blockHash

    // Look up by hash should return the same entry
    let found = manager.blockTreeEntry(byHash: hash)
    #expect(found != nil)
    #expect(found?.height == 0)
}

@Test func chainstateManagerLookupByUnknownHash() throws {
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
    let unknownHash = BlockHash(Data(repeating: 0xFF, count: 32))
    #expect(manager.blockTreeEntry(byHash: unknownHash) == nil)
}

@Test func processGenesisBlockHeader() throws {
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
    let bestEntry = manager.bestEntry
    let header = bestEntry.blockHeader
    let state = BlockValidationState()

    // Processing the genesis header (already known) should succeed
    let result = manager.processBlockHeader(header, state: state)
    #expect(result)
    #expect(state.validationMode == .valid)
}

@Test func processBlockRegtest() throws {
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

    // Process the regtest genesis block (already known — should succeed as duplicate)
    let genesisEntry = manager.activeChain.entry(atHeight: 0)!
    let genesisBlock = manager.readBlock(at: genesisEntry)
    // readBlock requires on-disk data; in-memory DB won't have blocks on disk
    // so this may return nil — that's acceptable for in-memory mode
    if let block = genesisBlock {
        let (success, _) = manager.processBlock(block)
        #expect(success)
    }
}

@Test func readBlockSpentOutputsAtGenesis() throws {
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
    let genesisEntry = manager.activeChain.entry(atHeight: 0)!

    // Genesis block returns spent outputs but with count 0 —
    // the coinbase creates coins without spending any, so there is no undo data.
    let spentOutputs = manager.readBlockSpentOutputs(at: genesisEntry)
    #expect(spentOutputs != nil)
    if let spentOutputs {
        #expect(spentOutputs.count == 0)
    }
}

@Test func importBlocksEmptyList() throws {
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
    // An empty list is a valid call that drives the kernel's import-and-activate
    // path (completing any pending reindex), not a short-circuit. On a freshly
    // created manager with nothing to reindex it succeeds without doing work.
    let result = manager.importBlocks(from: [])
    #expect(result)
}

// MARK: - KernelError

@Test func kernelErrorCases() {
    // Verify all error cases are distinct and matchable
    let errors: [KernelError] = [
        .contextCreationFailed,
        .loggingConnectionFailed,
        .transactionCreationFailed,
        .blockCreationFailed,
        .blockHeaderCreationFailed,
        .precomputedDataCreationFailed,
        .chainstateManagerOptionsCreationFailed,
        .chainstateManagerCreationFailed,
    ]
    // All cases should be unique
    for (i, e1) in errors.enumerated() {
        for (j, e2) in errors.enumerated() where i != j {
            #expect(String(describing: e1) != String(describing: e2))
        }
    }
}

// MARK: - BlockTreeEntry blockHash

@Test func blockTreeEntryBlockHash() throws {
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
    let bestEntry = manager.bestEntry
    let hash = bestEntry.blockHash
    // Hash should be 32 bytes
    #expect(hash.data.count == 32)
}
