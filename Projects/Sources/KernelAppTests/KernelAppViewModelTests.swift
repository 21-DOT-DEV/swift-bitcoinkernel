//
//  KernelAppViewModelTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2022-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

//  Drives the design of KernelAppViewModel — start/stop lifecycle,
//  snapshot translation, reindex paths, and settings-change policies.

import BitcoinKernel
import Foundation
import Testing
import Tor
@testable import KernelApp

// MARK: - Test factory

/// Build a view model wired to in-memory regtest, returning the parts
/// individual tests need to inspect (settings + mock + temp directory).
@MainActor
private func makeViewModel(
    chainType: ChainType = .regtest,
    endpoint: URL? = URL(string: "https://example.test/api"),
    routeThroughTor: Bool = false,
    bestTipHeight: Int = 0,
    bestTipHash: Data? = nil
) -> (vm: KernelAppViewModel, settings: KernelAppSettings, mock: MockBlockSource, tmpDir: URL) {
    let suite = "dev.21.KernelAppViewModelTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)

    let settings = KernelAppSettings(defaults: defaults)
    settings.chainType = chainType
    settings.blockSourceEndpoint = endpoint
    settings.routeDownloadsThroughTor = routeThroughTor

    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("KernelAppViewModelTests-\(UUID().uuidString)", isDirectory: true)
    settings.dataDirectoryOverride = tmpDir

    // Resolved later — at view-model start time, the manager has been
    // built and we can read its actual genesis hash. For now use a
    // placeholder; tests that exercise the happy path override via
    // `mock.setBestTip(...)` after start.
    let placeholderHash = bestTipHash ?? Data(repeating: 0xAA, count: 32)
    let mock = MockBlockSource(bestTip: BlockTip(hash: placeholderHash, height: bestTipHeight))

    let vm = KernelAppViewModel(
        settings: settings,
        tor: TorViewModel(subsystem: "test.KernelAppViewModelTests"),
        kernelFactory: { chainType, dir, threads, reindex in
            try await ResidentKernel.make(
                chainType: chainType,
                dataDirectory: dir,
                workerThreads: threads,
                reindex: reindex,
                inMemoryDatabases: true
            )
        },
        blockSourceFactory: { _, _ in mock }
    )
    return (vm, settings, mock, tmpDir)
}

// MARK: - Factory spy

/// Captures the arguments each ``KernelAppViewModel/KernelFactory`` call is
/// invoked with. Wraps the standard in-memory regtest factory so tests can
/// observe the `reindex:` argument while still getting a working kernel.
@MainActor
private final class KernelFactorySpy {
    struct Call: Sendable {
        let chainType: ChainType
        let dataDirectory: URL
        let workerThreads: Int32
        let reindex: ReindexMode?
    }

    private(set) var calls: [Call] = []

    func factory() -> KernelAppViewModel.KernelFactory {
        // Note: persistent storage (not in-memory). After a `(true, true)`
        // wipe + reopen, accessing `bestEntry` SEGVs at the C layer because
        // `btck_chainstate_manager_get_best_entry` returns null and the C
        // accessors don't null-guard. See
        // bitcoin/bitcoin#35293 (https://github.com/bitcoin/bitcoin/issues/35293).
        // Tests using this spy must clean up `tmpDir` themselves.
        return { @Sendable [weak self] chain, dir, threads, reindex in
            await MainActor.run {
                self?.calls.append(Call(
                    chainType: chain,
                    dataDirectory: dir,
                    workerThreads: threads,
                    reindex: reindex
                ))
            }
            return try await ResidentKernel.make(
                chainType: chain,
                dataDirectory: dir,
                workerThreads: threads,
                reindex: reindex,
                inMemoryDatabases: false
            )
        }
    }
}

@Suite("KernelAppViewModel — Lifecycle", .kernelSerialized)
@MainActor
struct KernelAppViewModelLifecycleTests {

    // MARK: - Endpoint precondition

    @Test("start() with no block-source endpoint fails fast and never opens a kernel")
    func startWithoutEndpointFailsFast() async {
        let parts = makeViewModel(endpoint: nil)
        defer { try? FileManager.default.removeItem(at: parts.tmpDir) }

        await parts.vm.start()

        if case .failed(let reason) = parts.vm.snapshot.phase {
            #expect(reason.lowercased().contains("block source"))
        } else {
            Issue.record("expected .failed phase, got \(parts.vm.snapshot.phase)")
        }
        #expect(parts.vm.residentKernel == nil)
    }

    // MARK: - Happy path: start → finished

    @Test("start() with mock claiming the local genesis as remote tip reaches .finished")
    func startReachesFinishedAtGenesis() async {
        let parts = makeViewModel()
        defer { try? FileManager.default.removeItem(at: parts.tmpDir) }

        // The mock's bestTip needs to match the kernel's genesis hash. We
        // can't know that until the kernel is built — so let the view
        // model start (which builds the kernel), then synchronize the
        // mock's claimed tip with the actual genesis, then wait.
        await parts.vm.start()
        if let kernel = parts.vm.residentKernel {
            let genesisHash = kernel.manager.bestEntry.blockHash.data
            parts.mock.setBestTip(BlockTip(hash: genesisHash, height: 0))
        }
        await parts.vm.syncTask?.value

        #expect(parts.vm.snapshot.phase == .finished)
        #expect(parts.vm.snapshot.localHeight == 0)
        #expect(parts.vm.residentKernel != nil)  // resident across run end
    }

    // MARK: - Stop teardown

    @Test("stop() while sync is mid-flight cancels the run and tears down the kernel")
    func stopMidSyncTearsDownKernel() async {
        let parts = makeViewModel()
        defer { try? FileManager.default.removeItem(at: parts.tmpDir) }

        // Freeze bestTip so the sync task hangs in .preparing forever.
        parts.mock.freezeBestTip()
        await parts.vm.start()

        // Yield so the sync task definitely begins its bestTip() call.
        await Task.yield()
        await Task.yield()

        await parts.vm.stop()

        #expect(parts.vm.snapshot.phase == .idle)
        #expect(parts.vm.residentKernel == nil)
        #expect(parts.vm.syncTask == nil)
    }
}

// MARK: - Reindex

@Suite("KernelAppViewModel — Reindex", .serialized)
@MainActor
struct KernelAppViewModelReindexTests {

    // MARK: - Rebuild-mode argument plumbing

    /// Records each `reindex:` argument the view model hands its kernel factory.
    private actor ReindexCallRecorder {
        private(set) var calls: [ReindexMode?] = []
        func record(_ mode: ReindexMode?) { calls.append(mode) }
    }

    /// Shared setup for both rebuild-mode tests: a view model whose kernel
    /// factory records the `reindex:` argument and then throws.
    ///
    /// Throwing keeps both tests off real databases, for two different reasons
    /// worth keeping straight:
    ///
    /// - `.full` **must** avoid a real reopen — reading the chain tip after a
    ///   wipe of both databases crashes inside the C library. See
    ///   [bitcoin/bitcoin#35293](https://github.com/bitcoin/bitcoin/issues/35293).
    /// - `.chainstate` no longer needs one — proving that a real reopen succeeds
    ///   moved down to `BlockchainSyncTeardownTests`
    ///   (`shutdownReleasesDataDirectoryBeforeReopen`), which is deterministic,
    ///   runs on every platform, and needs no simulator.
    ///
    /// What remains here is the view model's own contract: it forwards the mode
    /// it was handed, unchanged.
    private func makeRecordingViewModel(
        label: String
    ) -> (vm: KernelAppViewModel, recorder: ReindexCallRecorder) {
        struct StubError: Error {}

        let suite = "dev.21.KernelAppViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let settings = KernelAppSettings(defaults: defaults)
        settings.chainType = .regtest
        settings.blockSourceEndpoint = URL(string: "https://example.test/api")!

        let recorder = ReindexCallRecorder()
        let factory: KernelAppViewModel.KernelFactory = { @Sendable _, _, _, reindex in
            await recorder.record(reindex)
            throw StubError()
        }
        let mock = MockBlockSource(
            bestTip: BlockTip(hash: Data(repeating: 0xAA, count: 32), height: 0)
        )

        let vm = KernelAppViewModel(
            settings: settings,
            tor: TorViewModel(subsystem: "test.KernelAppViewModelReindexTests.\(label)"),
            kernelFactory: factory,
            blockSourceFactory: { _, _ in mock }
        )
        return (vm, recorder)
    }

    // MARK: - Chainstate-only reindex

    @Test("requestReindex(.chainstate) passes the chainstate wipe flag to the kernel factory")
    func requestReindexChainstateInvokesFactoryWithCorrectFlag() async {
        let parts = makeRecordingViewModel(label: "chainstate")

        await parts.vm.start()                       // records nil
        await parts.vm.requestReindex(.chainstate)   // records .chainstate

        let calls = await parts.recorder.calls
        #expect(calls.count == 2)
        #expect(calls[0] == nil)
        #expect(calls[1] == .chainstate)
    }

    // MARK: - Full reindex

    @Test("requestReindex(.full) passes the full wipe flag to the kernel factory")
    func requestReindexFullInvokesFactoryWithCorrectFlag() async {
        let parts = makeRecordingViewModel(label: "full")

        await parts.vm.start()                 // records nil
        await parts.vm.requestReindex(.full)   // records .full

        let calls = await parts.recorder.calls
        #expect(calls.count == 2)
        #expect(calls[0] == nil)
        #expect(calls[1] == .full)
    }
}

// MARK: - Settings-change policy

@Suite("KernelAppViewModel — Settings-change policy", .serialized, .kernelSerialized)
@MainActor
struct KernelAppViewModelSettingsChangeTests {

    /// Same recipe as `KernelAppViewModelReindexTests.makeWithSpy` — a
    /// settings model backed by a volatile UserDefaults suite, a recording
    /// kernel factory that builds real regtest kernels on persistent disk,
    /// and a mock block source.
    private func makeWithSpy() -> (
        vm: KernelAppViewModel,
        settings: KernelAppSettings,
        spy: KernelFactorySpy,
        mock: MockBlockSource,
        tmpDir: URL
    ) {
        let suite = "dev.21.KernelAppViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let settings = KernelAppSettings(defaults: defaults)
        settings.chainType = .regtest
        settings.blockSourceEndpoint = URL(string: "https://example.test/api")!
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KernelAppViewModelTests-\(UUID().uuidString)", isDirectory: true)
        settings.dataDirectoryOverride = tmpDir

        let mock = MockBlockSource(bestTip: BlockTip(
            hash: Data(repeating: 0xAA, count: 32),
            height: 0
        ))
        let spy = KernelFactorySpy()

        let vm = KernelAppViewModel(
            settings: settings,
            tor: TorViewModel(subsystem: "test.KernelAppViewModelSettingsChangeTests"),
            kernelFactory: spy.factory(),
            blockSourceFactory: { _, _ in mock }
        )
        return (vm, settings, spy, mock, tmpDir)
    }

    /// Drive a `start()` to `.finished` so subsequent tests have a valid
    /// `lastAppliedSnapshot` and a resident kernel to diff against.
    private func bringUpAndFinish(
        _ parts: (vm: KernelAppViewModel, settings: KernelAppSettings, spy: KernelFactorySpy, mock: MockBlockSource, tmpDir: URL)
    ) async {
        await parts.vm.start()
        if let kernel = parts.vm.residentKernel {
            let genesisHash = kernel.manager.bestEntry.blockHash.data
            parts.mock.setBestTip(BlockTip(hash: genesisHash, height: 0))
        }
        await parts.vm.syncTask?.value
    }

    // MARK: - No baseline

    @Test("applySettingsChange() before start() is a no-op and does not open a kernel")
    func beforeStartNoOp() async {
        let parts = makeWithSpy()
        defer { try? FileManager.default.removeItem(at: parts.tmpDir) }

        await parts.vm.applySettingsChange()

        #expect(parts.spy.calls.isEmpty)
        #expect(parts.vm.residentKernel == nil)
        #expect(parts.vm.syncTask == nil)
        #expect(parts.vm.lastAppliedSnapshot == nil)
    }

    // MARK: - .none

    @Test("applySettingsChange() with no effective change is a no-op")
    func identicalSettingsNoOp() async {
        let parts = makeWithSpy()
        await bringUpAndFinish(parts)
        #expect(parts.spy.calls.count == 1)
        let snapshotAfterStart = parts.vm.lastAppliedSnapshot

        await parts.vm.applySettingsChange()

        #expect(parts.spy.calls.count == 1, "no new kernel built for a no-op apply")
        #expect(parts.vm.lastAppliedSnapshot == snapshotAfterStart)

        await parts.vm.stop()
        try? FileManager.default.removeItem(at: parts.tmpDir)
    }

    // MARK: - .restartKernel

    @Test("workerThreadCount change triggers kernel rebuild via applySettingsChange()")
    func workerThreadChangeRestartsKernel() async {
        let parts = makeWithSpy()
        await bringUpAndFinish(parts)
        #expect(parts.spy.calls.count == 1)
        #expect(parts.spy.calls[0].workerThreads == 0)

        parts.settings.workerThreadCount = 2

        await parts.vm.applySettingsChange()
        if let kernel = parts.vm.residentKernel {
            let genesisHash = kernel.manager.bestEntry.blockHash.data
            parts.mock.setBestTip(BlockTip(hash: genesisHash, height: 0))
        }
        await parts.vm.syncTask?.value

        #expect(parts.spy.calls.count == 2, "kernel should be rebuilt")
        #expect(parts.spy.calls[1].workerThreads == 2)
        #expect(parts.spy.calls[1].reindex == nil, "plain restart, not a reindex")
        #expect(parts.vm.lastAppliedSnapshot?.workerThreadCount == 2)

        await parts.vm.stop()
        try? FileManager.default.removeItem(at: parts.tmpDir)
    }

    // MARK: - .restartSync

    @Test("blockSourceEndpoint change respawns sync without rebuilding the kernel")
    func endpointChangeRestartsSyncOnly() async {
        let parts = makeWithSpy()
        await bringUpAndFinish(parts)
        #expect(parts.spy.calls.count == 1)

        parts.settings.blockSourceEndpoint = URL(string: "https://different.example/api")!

        await parts.vm.applySettingsChange()
        if let kernel = parts.vm.residentKernel {
            let genesisHash = kernel.manager.bestEntry.blockHash.data
            parts.mock.setBestTip(BlockTip(hash: genesisHash, height: 0))
        }
        await parts.vm.syncTask?.value

        #expect(parts.spy.calls.count == 1, "kernel must NOT be rebuilt for a sync-only change")
        #expect(parts.vm.residentKernel != nil, "kernel stays resident across a sync-only restart")
        #expect(parts.vm.lastAppliedSnapshot?.blockSourceEndpoint?.absoluteString
                == "https://different.example/api")

        await parts.vm.stop()
        try? FileManager.default.removeItem(at: parts.tmpDir)
    }

    // MARK: - .restartSync — Tor routing flip mid-run

    @Test("enabling Tor routing mid-run enters .waitingForTor without rebuilding the kernel")
    func torEnableDuringRunEntersWaitingForTor() async {
        let parts = makeWithSpy()
        await bringUpAndFinish(parts)
        #expect(parts.spy.calls.count == 1)

        // The TorViewModel in this suite is a plain, never-started
        // instance (displayState == .disabled, isReady == false), so
        // flipping the routing setting should park the VM in
        // .waitingForTor — not .failed.
        parts.settings.routeDownloadsThroughTor = true

        await parts.vm.applySettingsChange()

        #expect(parts.vm.snapshot.phase == .waitingForTor,
                "expected .waitingForTor, got \(parts.vm.snapshot.phase)")
        #expect(parts.spy.calls.count == 1, "no kernel rebuild on sync-only change")
        #expect(parts.vm.syncTask == nil, "sync task should be cancelled while waiting")

        await parts.vm.stop()
        try? FileManager.default.removeItem(at: parts.tmpDir)
    }

    // MARK: - Data-directory isolation across chain switches

    @Test("chainType switch opens a different data directory and leaves the old chain's state intact")
    func chainSwitchIsolatesDataDirectories() async {
        // Set up against a common parent dir so the per-chain subdirs
        // live side-by-side and we can inspect both after the switch.
        let suite = "dev.21.KernelAppViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let settings = KernelAppSettings(defaults: defaults)
        settings.chainType = .regtest
        settings.blockSourceEndpoint = URL(string: "https://example.test/api")!

        // Use a fixed parent — each chain switch should write to its own
        // subdirectory computed from `effectiveDataDirectory`. We want
        // the switch's two effective dirs to be distinct, so we must NOT
        // pin `dataDirectoryOverride` (that would give both chains the
        // same path).
        //
        // Instead, rely on the defaultDataDirectory(for:) logic which
        // already namespaces per chain under Application Support. In a
        // test environment Application Support works fine — we'll clean
        // up both sub-dirs afterwards.
        let regtestDir = settings.effectiveDataDirectory

        let mock = MockBlockSource(bestTip: BlockTip(
            hash: Data(repeating: 0xAA, count: 32),
            height: 0
        ))
        let spy = KernelFactorySpy()
        let vm = KernelAppViewModel(
            settings: settings,
            tor: TorViewModel(subsystem: "test.KernelAppViewModelSettingsChangeTests.chainSwitch"),
            kernelFactory: spy.factory(),
            blockSourceFactory: { _, _ in mock }
        )

        // Start on regtest.
        await vm.start()
        if let kernel = vm.residentKernel {
            let genesisHash = kernel.manager.bestEntry.blockHash.data
            mock.setBestTip(BlockTip(hash: genesisHash, height: 0))
        }
        await vm.syncTask?.value
        #expect(spy.calls.count == 1)
        #expect(spy.calls[0].chainType == .regtest)
        #expect(spy.calls[0].dataDirectory == regtestDir)

        // Record the regtest directory's contents after the first run.
        let regtestContentsBefore = (try? FileManager.default
            .contentsOfDirectory(atPath: regtestDir.path)) ?? []
        #expect(!regtestContentsBefore.isEmpty,
                "regtest run should have left at least one file on disk")

        // Switch to signet via applySettingsChange.
        settings.chainType = .signet
        let signetDir = settings.effectiveDataDirectory
        #expect(signetDir != regtestDir,
                "per-chain subdir layout should produce distinct paths")

        await vm.applySettingsChange()
        if let kernel = vm.residentKernel {
            let genesisHash = kernel.manager.bestEntry.blockHash.data
            mock.setBestTip(BlockTip(hash: genesisHash, height: 0))
        }
        await vm.syncTask?.value

        #expect(spy.calls.count == 2)
        #expect(spy.calls[1].chainType == .signet)
        #expect(spy.calls[1].dataDirectory == signetDir)

        // Regtest dir must still contain the files the first run wrote.
        let regtestContentsAfter = (try? FileManager.default
            .contentsOfDirectory(atPath: regtestDir.path)) ?? []
        #expect(Set(regtestContentsBefore) == Set(regtestContentsAfter),
                "chain switch must not touch the previous chain's data")

        await vm.stop()
        try? FileManager.default.removeItem(at: regtestDir)
        try? FileManager.default.removeItem(at: signetDir)
    }
}
