//
//  ResidentKernel.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import BitcoinKernel
import Foundation

// MARK: - ReindexMode

/// Reindex variants matching Bitcoin Core's user-facing CLI vocabulary
/// (`-reindex-chainstate` vs. `-reindex`).
enum ReindexMode: Sendable, Equatable {
    /// Wipe chainstate (UTXO db) only; keep the block index. Replays
    /// validation against existing block files. Maps to Core's
    /// `-reindex-chainstate`.
    case chainstate

    /// Wipe both chainstate and block tree dbs; re-process every block
    /// file from scratch. Maps to Core's `-reindex`.
    case full

    /// Title surfaced in the SwiftUI confirmation alert.
    var confirmationTitle: String {
        switch self {
        case .chainstate: return "Reindex Chainstate"
        case .full:       return "Full Reindex"
        }
    }

    /// Body surfaced in the SwiftUI confirmation alert.
    var confirmationMessage: String {
        switch self {
        case .chainstate:
            return "This wipes the chainstate database and rebuilds it from the stored block files. Sync will restart."
        case .full:
            return "This wipes both the block index and chainstate databases and rebuilds them from the stored block files. Sync will restart."
        }
    }

    /// Pair of wipe flags consumed by
    /// ``ChainstateManagerOptions/setWipeDBs(blockTreeDB:chainstateDB:)``.
    fileprivate var wipeFlags: (blockTreeDB: Bool, chainstateDB: Bool) {
        switch self {
        case .chainstate: return (false, true)
        case .full:       return (true,  true)
        }
    }
}

// MARK: - ResidentKernel

/// Bundles the kernel ``Context`` and ``ChainstateManager`` that
/// ``KernelAppViewModel`` keeps alive across sync-task lifecycles, per
/// Q1's hybrid-resident decision.
///
/// Construction is async because LevelDB open can be slow on mainnet — we
/// dispatch to a background priority so the MainActor view model stays
/// responsive while the kernel is opening.
struct ResidentKernel: Sendable {
    let context: Context
    let manager: ChainstateManager

    /// Construct a fresh kernel rooted at `dataDirectory`.
    ///
    /// - Parameters:
    ///   - chainType: The Bitcoin network. Determines chain parameters.
    ///   - dataDirectory: Where the block tree and chainstate dbs live.
    ///     Created (with intermediates) if it doesn't exist; marked
    ///     excluded from backup per Apple guidance.
    ///   - workerThreads: Validation thread-pool size; `0` = kernel auto.
    ///     Clamped to the kernel's internal cap of 15.
    ///   - reindex: Wipe options for restart-after-corruption flows. `nil`
    ///     for the steady-state happy path.
    ///   - inMemoryDatabases: When `true`, both the block tree and
    ///     chainstate dbs live in RAM. Test-only — production always uses
    ///     persistent storage.
    static func make(
        chainType: ChainType,
        dataDirectory: URL,
        workerThreads: Int32 = 0,
        reindex: ReindexMode? = nil,
        inMemoryDatabases: Bool = false
    ) async throws -> ResidentKernel {
        // LevelDB open is blocking and can take several seconds on
        // mainnet; do not stall the MainActor.
        try await Task.detached(priority: .userInitiated) {
            try makeSync(
                chainType: chainType,
                dataDirectory: dataDirectory,
                workerThreads: workerThreads,
                reindex: reindex,
                inMemoryDatabases: inMemoryDatabases
            )
        }.value
    }

    /// Synchronous construction body — separated so the async wrapper can
    /// run it on a detached task while keeping the body itself simple.
    private static func makeSync(
        chainType: ChainType,
        dataDirectory: URL,
        workerThreads: Int32,
        reindex: ReindexMode?,
        inMemoryDatabases: Bool
    ) throws -> ResidentKernel {
        // Ensure the directory exists and is excluded from backup.
        try KernelAppSettings.prepareDataDirectory(at: dataDirectory)

        // Build the context.
        let params = ChainParameters(chainType)
        let ctxOpts = ContextOptions()
        ctxOpts.setChainParams(params)
        let context = try Context(options: ctxOpts)

        // Build the chainstate-manager options.
        let options = try ChainstateManagerOptions(
            context: context,
            dataDirectory: dataDirectory.path
        )
        options.setWorkerThreads(workerThreads)
        if let reindex {
            let flags = reindex.wipeFlags
            options.setWipeDBs(blockTreeDB: flags.blockTreeDB, chainstateDB: flags.chainstateDB)
        }
        if inMemoryDatabases {
            options.setBlockTreeDBInMemory(true)
            options.setChainstateDBInMemory(true)
        }

        let manager = try ChainstateManager(options: options)
        return ResidentKernel(context: context, manager: manager)
    }

    /// Build a ``BlockchainSync`` engine bound to this resident kernel
    /// against the given block source. Cheap value-type construction —
    /// `BlockchainSync.init` does no work; the loop only starts on the
    /// first call to ``BlockchainSync/updates()``.
    func makeSync(source: any BlockSource) -> BlockchainSync {
        BlockchainSync(manager: manager, source: source, context: context)
    }
}
