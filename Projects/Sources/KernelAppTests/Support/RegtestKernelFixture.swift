//
//  RegtestKernelFixture.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2022-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import BitcoinKernel
import Foundation

/// Spins up a minimal in-memory regtest kernel for view-model tests.
///
/// Mirrors the helper in `Tests/BitcoinKernelTests/BlockchainSyncEngineTests.swift`
/// (the codebase's established pattern) but lives in this target so KernelApp
/// tests can build their own kernels without touching disk.
@MainActor
enum RegtestKernelFixture {

    /// Bundle of artifacts produced by a fresh regtest open.
    /// `tmpDir` is reserved for tests that opt out of in-memory mode and
    /// want a real path; it is cleaned up by the caller.
    struct Artifacts {
        let context: Context
        let manager: ChainstateManager
        let tmpDir: URL
    }

    /// Build a fresh regtest kernel at an isolated temp directory.
    ///
    /// - Parameter inMemory: When `true` (default), the block-tree and
    ///   chainstate databases live in RAM — fast and self-cleaning.
    static func make(inMemory: Bool = true) throws -> Artifacts {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let params = ChainParameters(.regtest)
        let ctxOpts = ContextOptions()
        ctxOpts.setChainParams(params)
        let context = try Context(options: ctxOpts)

        let options = try ChainstateManagerOptions(context: context, dataDirectory: tmpDir.path)
        if inMemory {
            options.setBlockTreeDBInMemory(true)
            options.setChainstateDBInMemory(true)
        }
        let manager = try ChainstateManager(options: options)
        return Artifacts(context: context, manager: manager, tmpDir: tmpDir)
    }
}
