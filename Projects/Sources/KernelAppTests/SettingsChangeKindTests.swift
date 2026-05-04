//
//  SettingsChangeKindTests.swift
//  21-DOT-DEV/Bitcoin
//
//  Phase B2 / T6.1: unit tests driving the design of the settings-change
//  classifier. Pure tests — no kernel, no filesystem (save for one
//  integration test against KernelAppSettings for the convenience init).
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import BitcoinKernel
import Foundation
import Testing
@testable import KernelApp

@Suite("SettingsChangeKind")
struct SettingsChangeKindTests {

    // MARK: Helpers

    private func snapshot(
        chainType: ChainType = .signet,
        dir: URL = URL(fileURLWithPath: "/tmp/signet"),
        workers: Int32 = 0,
        endpoint: URL? = URL(string: "https://mempool.space/signet/api"),
        tor: Bool = false
    ) -> KernelAppSettingsSnapshot {
        KernelAppSettingsSnapshot(
            chainType: chainType,
            effectiveDataDirectory: dir,
            workerThreadCount: workers,
            blockSourceEndpoint: endpoint,
            routeDownloadsThroughTor: tor
        )
    }

    // MARK: T6.1 — classifier matrix

    @Test("identical snapshots classify as .none")
    func identicalSnapshotsClassifyAsNone() {
        let s = snapshot()
        #expect(SettingsChangeKind.classify(previous: s, current: s) == .none)
    }

    @Test("chainType change classifies as .restartKernel")
    func chainTypeChangeRequiresKernelRestart() {
        let before = snapshot(chainType: .signet, dir: URL(fileURLWithPath: "/tmp/signet"))
        let after = snapshot(chainType: .testnet, dir: URL(fileURLWithPath: "/tmp/testnet"))
        #expect(SettingsChangeKind.classify(previous: before, current: after) == .restartKernel)
    }

    @Test("effectiveDataDirectory change classifies as .restartKernel")
    func dataDirChangeRequiresKernelRestart() {
        let before = snapshot(dir: URL(fileURLWithPath: "/tmp/a"))
        let after = snapshot(dir: URL(fileURLWithPath: "/tmp/b"))
        #expect(SettingsChangeKind.classify(previous: before, current: after) == .restartKernel)
    }

    @Test("workerThreadCount change classifies as .restartKernel")
    func workerThreadChangeRequiresKernelRestart() {
        let before = snapshot(workers: 2)
        let after = snapshot(workers: 4)
        #expect(SettingsChangeKind.classify(previous: before, current: after) == .restartKernel)
    }

    @Test("blockSourceEndpoint change classifies as .restartSync")
    func endpointChangeRequiresSyncRestart() {
        let before = snapshot(endpoint: URL(string: "https://a.example/api"))
        let after = snapshot(endpoint: URL(string: "https://b.example/api"))
        #expect(SettingsChangeKind.classify(previous: before, current: after) == .restartSync)
    }

    @Test("blockSourceEndpoint nil → non-nil classifies as .restartSync")
    func endpointNilToSetRequiresSyncRestart() {
        let before = snapshot(endpoint: nil)
        let after = snapshot(endpoint: URL(string: "https://a.example/api"))
        #expect(SettingsChangeKind.classify(previous: before, current: after) == .restartSync)
    }

    @Test("routeDownloadsThroughTor toggle classifies as .restartSync")
    func torToggleRequiresSyncRestart() {
        let before = snapshot(tor: false)
        let after = snapshot(tor: true)
        #expect(SettingsChangeKind.classify(previous: before, current: after) == .restartSync)
    }

    // MARK: Priority — kernel-level dominates sync-level

    @Test("kernel-level + sync-level change together classifies as .restartKernel (most aggressive wins)")
    func kernelChangeDominatesSyncChange() {
        let before = snapshot(
            chainType: .signet,
            endpoint: URL(string: "https://a.example/api")
        )
        let after = snapshot(
            chainType: .testnet,
            endpoint: URL(string: "https://b.example/api")
        )
        #expect(SettingsChangeKind.classify(previous: before, current: after) == .restartKernel)
    }

    // MARK: Convenience — snapshot from live settings

    @MainActor
    @Test("KernelAppSettingsSnapshot(settings:) captures current state")
    func snapshotFromLiveSettings() {
        let suite = "dev.21.SettingsChangeKindTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = KernelAppSettings(defaults: defaults)
        settings.chainType = .regtest
        settings.workerThreadCount = 2
        settings.routeDownloadsThroughTor = true

        let snap = KernelAppSettingsSnapshot(settings: settings)

        #expect(snap.chainType == .regtest)
        #expect(snap.workerThreadCount == 2)
        #expect(snap.effectiveDataDirectory == settings.effectiveDataDirectory)
        #expect(snap.blockSourceEndpoint == settings.blockSourceEndpoint)
        #expect(snap.routeDownloadsThroughTor == true)
    }

    @MainActor
    @Test("Two snapshots of an unchanged settings model are equal")
    func snapshotStableAcrossReads() {
        let suite = "dev.21.SettingsChangeKindTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = KernelAppSettings(defaults: defaults)
        let first = KernelAppSettingsSnapshot(settings: settings)
        let second = KernelAppSettingsSnapshot(settings: settings)

        #expect(first == second)
        #expect(SettingsChangeKind.classify(previous: first, current: second) == .none)
    }
}
