//
//  KernelAppViewModelTorTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2022-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

//  Integration tests for `KernelAppViewModel`'s Tor wait-and-kick state
//  machine. Uses the shared `FakeTorSession` + `SessionFactory` helpers
//  from `Sources/SharedTests/` so we don't need a live Tor daemon to
//  exercise bootstrapping, readiness, and failure paths.
//
//  The fake session always advertises `HostPort(host: "127.0.0.1",
//  port: 9050)` once released — that literal is the expected argument
//  surfaced to the `blockSourceFactory` in the plumbing test below.

import BitcoinKernel
import Foundation
import Testing
import Tor
@testable import KernelApp

// MARK: - Parts builder

@MainActor
private struct TorTestParts {
    let vm: KernelAppViewModel
    let settings: KernelAppSettings
    let tor: TorViewModel
    let fake: FakeTorSession
    let mock: MockBlockSource
    let tmpDir: URL
    /// Every `HostPort` passed to the block-source factory, captured in
    /// invocation order so tests can assert on plumbing.
    let capturedSocks: SocksRecorder
}

@MainActor
private final class SocksRecorder {
    private(set) var calls: [HostPort?] = []
    func record(_ hp: HostPort?) { calls.append(hp) }
}

/// Build a fully wired view model backed by an in-memory regtest kernel,
/// a releasable `FakeTorSession`, and a recording block-source factory.
@MainActor
private func makeTorParts(
    routeThroughTor: Bool = true,
    backoffSchedule: [Duration] = [.milliseconds(20)],
    sessionMode: FakeTorSession.Mode = .blockUntilReleased
) -> TorTestParts {
    let suite = "dev.21.KernelAppViewModelTorTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)

    let settings = KernelAppSettings(defaults: defaults)
    settings.chainType = .regtest
    settings.blockSourceEndpoint = URL(string: "https://example.test/api")!
    settings.routeDownloadsThroughTor = routeThroughTor

    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("KernelAppViewModelTorTests-\(UUID().uuidString)", isDirectory: true)
    settings.dataDirectoryOverride = tmpDir

    let fake = FakeTorSession(mode: sessionMode)
    let tor = TorViewModel(
        subsystem: "test.KernelAppViewModelTorTests",
        backoffSchedule: backoffSchedule,
        makeSession: { _ in fake }
    )

    let mock = MockBlockSource(bestTip: BlockTip(
        hash: Data(repeating: 0xAA, count: 32),
        height: 0
    ))
    let recorder = SocksRecorder()

    let vm = KernelAppViewModel(
        settings: settings,
        tor: tor,
        kernelFactory: { chain, dir, threads, reindex in
            try await ResidentKernel.make(
                chainType: chain,
                dataDirectory: dir,
                workerThreads: threads,
                reindex: reindex,
                inMemoryDatabases: true
            )
        },
        blockSourceFactory: { _, socks in
            // Main-actor-isolated recording is safe here — the factory
            // is only invoked from KernelAppViewModel which is
            // @MainActor. The `assumeIsolated` keeps the closure
            // `@Sendable` without forcing a hop.
            MainActor.assumeIsolated {
                recorder.record(socks)
            }
            return mock
        }
    )
    return TorTestParts(
        vm: vm,
        settings: settings,
        tor: tor,
        fake: fake,
        mock: mock,
        tmpDir: tmpDir,
        capturedSocks: recorder
    )
}

// MARK: - waitFor helper

/// Local polling helper — see `Sources/SharedTests/WaitFor.swift`.
/// Re-exported here only so the compiler finds it without an explicit
/// module prefix. (Test-target source sharing means the function is
/// compiled into this target too.)

// MARK: - Suite

@Suite("KernelAppViewModel — Tor integration", .serialized)
@MainActor
struct KernelAppViewModelTorTests {

    // MARK: - Wait-for-Tor entry

    @Test("start() with Tor routing and Tor not ready parks in .waitingForTor")
    func startParksInWaitingForTor() async throws {
        let parts = makeTorParts()
        defer { try? FileManager.default.removeItem(at: parts.tmpDir) }

        #expect(!parts.tor.isReady, "fake Tor must not be pre-bootstrapped")

        await parts.vm.start()

        #expect(parts.vm.snapshot.phase == .waitingForTor)
        #expect(parts.vm.syncTask == nil, "no sync task while waiting for Tor")
        #expect(parts.vm.residentKernel == nil, "kernel not opened until Tor is ready")
        #expect(parts.capturedSocks.calls.isEmpty, "block source factory not called yet")

        await parts.vm.stop()
    }

    // MARK: - Auto-kick on Tor ready

    @Test("Tor becoming ready while waiting auto-kicks the sync with a SOCKS endpoint")
    func torReadyAutoKicksSync() async throws {
        let parts = makeTorParts()
        defer { try? FileManager.default.removeItem(at: parts.tmpDir) }

        // Drive TorViewModel through .starting, then land in the
        // wait-for-Tor observer.
        parts.tor.start()
        await parts.vm.start()
        #expect(parts.vm.snapshot.phase == .waitingForTor)

        // Release the FakeTorSession bootstrap gate — TorViewModel
        // flips to .running and isReady == true. The observer polls
        // every 250ms; give it up to a second to notice.
        await parts.fake.releaseBootstrap()
        try await waitFor(timeout: .seconds(2)) { parts.tor.isReady }
        try await waitFor(timeout: .seconds(2)) {
            parts.vm.snapshot.phase != .waitingForTor
        }

        // After kick: kernel was opened and the factory was called with
        // the fake's SOCKS endpoint.
        #expect(parts.vm.residentKernel != nil)
        #expect(parts.capturedSocks.calls.count == 1)
        #expect(parts.capturedSocks.calls.first ?? nil == HostPort(host: "127.0.0.1", port: 9050))

        // Let the sync run to completion and tear down.
        if let kernel = parts.vm.residentKernel {
            let genesisHash = kernel.manager.bestEntry.blockHash.data
            parts.mock.setBestTip(BlockTip(hash: genesisHash, height: 0))
        }
        await parts.vm.syncTask?.value
        #expect(parts.vm.snapshot.phase == .finished)

        await parts.vm.stop()
    }

    // MARK: - Stop during wait

    @Test("stop() during .waitingForTor cancels the observer and returns to .idle")
    func stopDuringWaitCancelsObserver() async throws {
        let parts = makeTorParts()
        defer { try? FileManager.default.removeItem(at: parts.tmpDir) }

        await parts.vm.start()
        #expect(parts.vm.snapshot.phase == .waitingForTor)

        await parts.vm.stop()
        #expect(parts.vm.snapshot.phase == .idle)

        // Even if Tor later becomes ready, the cancelled observer must
        // NOT spring back to life and open a kernel.
        parts.tor.start()
        await parts.fake.releaseBootstrap()
        try await waitFor(timeout: .seconds(1)) { parts.tor.isReady }
        try? await Task.sleep(for: .milliseconds(400))

        #expect(parts.vm.residentKernel == nil,
                "stopped observer must not rebuild the kernel post-hoc")
        #expect(parts.vm.snapshot.phase == .idle)
        #expect(parts.capturedSocks.calls.isEmpty)
    }

    // MARK: - Tor failure propagation

    @Test("Terminal Tor failure while waiting surfaces as .failed(...)")
    func terminalTorFailureSurfacesAsFailed() async throws {
        // Schedule exactly one retry delay — so initial + 1 retry = 2
        // throwing attempts before give-up. Both sessions throw, which
        // lands TorViewModel in .failed with nextRetryAt == nil.
        let parts = makeTorParts(
            backoffSchedule: [.milliseconds(10)],
            sessionMode: .startThrows
        )
        defer { try? FileManager.default.removeItem(at: parts.tmpDir) }

        parts.tor.start()
        await parts.vm.start()
        #expect(parts.vm.snapshot.phase == .waitingForTor)

        // Wait for TorViewModel to exhaust its retry schedule.
        try await waitFor(timeout: .seconds(2)) {
            parts.tor.displayState == .failed && parts.tor.nextRetryAt == nil
        }
        // Observer polls at 250ms; give it a wide margin.
        try await waitFor(timeout: .seconds(2)) {
            if case .failed = parts.vm.snapshot.phase { return true }
            return false
        }

        if case .failed(let reason) = parts.vm.snapshot.phase {
            #expect(reason.lowercased().contains("tor"),
                    "expected Tor-related failure, got: \(reason)")
        } else {
            Issue.record("expected .failed phase, got \(parts.vm.snapshot.phase)")
        }
        #expect(parts.vm.residentKernel == nil)
        #expect(parts.capturedSocks.calls.isEmpty)

        await parts.vm.stop()
    }

    // MARK: - Direct path (no Tor)

    @Test("start() with Tor routing off passes nil SOCKS to the block source factory")
    func directPathPassesNilSocks() async throws {
        let parts = makeTorParts(routeThroughTor: false)
        defer { try? FileManager.default.removeItem(at: parts.tmpDir) }

        await parts.vm.start()
        #expect(parts.vm.snapshot.phase != .waitingForTor,
                "direct path must not enter .waitingForTor")

        if let kernel = parts.vm.residentKernel {
            let genesisHash = kernel.manager.bestEntry.blockHash.data
            parts.mock.setBestTip(BlockTip(hash: genesisHash, height: 0))
        }
        await parts.vm.syncTask?.value

        #expect(parts.capturedSocks.calls.count == 1)
        #expect(parts.capturedSocks.calls.first ?? HostPort.localhost(1) == nil,
                "direct path must pass nil SOCKS to factory")

        await parts.vm.stop()
    }

    // MARK: - Tor ready at start time

    @Test("start() with Tor already ready skips .waitingForTor and plumbs SOCKS directly")
    func torAlreadyReadyBypassesWait() async throws {
        let parts = makeTorParts()
        defer { try? FileManager.default.removeItem(at: parts.tmpDir) }

        // Bring Tor up BEFORE calling start(). Use a fresh session for
        // this since the shared fake is already fronted by
        // TorViewModel's makeSession closure.
        parts.tor.start()
        await parts.fake.releaseBootstrap()
        try await waitFor(timeout: .seconds(2)) { parts.tor.isReady }

        await parts.vm.start()

        #expect(parts.vm.snapshot.phase != .waitingForTor,
                "ready Tor must skip the wait state")
        #expect(parts.capturedSocks.calls.count == 1)
        #expect(parts.capturedSocks.calls.first ?? nil == HostPort(host: "127.0.0.1", port: 9050))

        if let kernel = parts.vm.residentKernel {
            let genesisHash = kernel.manager.bestEntry.blockHash.data
            parts.mock.setBestTip(BlockTip(hash: genesisHash, height: 0))
        }
        await parts.vm.syncTask?.value
        #expect(parts.vm.snapshot.phase == .finished)

        await parts.vm.stop()
    }
}
