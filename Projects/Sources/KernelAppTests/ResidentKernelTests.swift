//
//  ResidentKernelTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2022-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

//  Drives the design of ResidentKernel — the bundle that pairs Context
//  + ChainstateManager and lives across sync-task lifecycles.

import BitcoinKernel
import Foundation
import Testing
@testable import KernelApp

@Suite("ResidentKernel")
@MainActor
struct ResidentKernelTests {

    // MARK: - Basic construction

    @Test("make(chainType:dataDirectory:inMemoryDatabases:) produces a working kernel at genesis")
    func makeProducesWorkingKernelAtGenesis() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResidentKernelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let kernel = try await ResidentKernel.make(
            chainType: .regtest,
            dataDirectory: tmpDir,
            inMemoryDatabases: true
        )

        // Genesis: a fresh regtest chain reports height 0.
        #expect(kernel.manager.bestEntry.height == 0)
    }

    // MARK: - makeSync wires the kernel to a BlockSource

    @Test("makeSync(source:) yields a BlockchainSync that drives this kernel to a tip from a mock source")
    func makeSyncDrivesKernelFromMockSource() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResidentKernelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let kernel = try await ResidentKernel.make(
            chainType: .regtest,
            dataDirectory: tmpDir,
            inMemoryDatabases: true
        )

        // Mock claims its tip is the local genesis — sync should finish
        // immediately without fetching anything.
        let genesisHash = kernel.manager.bestEntry.blockHash.data
        let mock = MockBlockSource(bestTip: BlockTip(hash: genesisHash, height: 0))

        let sync = kernel.makeSync(source: mock)

        var states: [BlockchainSync.Update.State] = []
        for await update in sync.updates() {
            states.append(update.state)
        }

        #expect(states.first == .preparing)
        #expect(states.last == .finished)
    }
}
