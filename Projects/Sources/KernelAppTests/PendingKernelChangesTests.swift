//
//  PendingKernelChangesTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2022-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

//  Pure tests for the draft-state value type that backs the Settings
//  tab's "pending changes" banner. Apply / count / summary-text
//  semantics are all value-level and exercised here without SwiftUI.

import BitcoinKernel
import Foundation
import Testing
@testable import KernelApp

@Suite("PendingKernelChanges")
struct PendingKernelChangesValueTests {

    // MARK: - Empty / count

    @Test("a freshly constructed draft is empty")
    func defaultIsEmpty() {
        let draft = PendingKernelChanges()
        #expect(draft.isEmpty)
        #expect(draft.count == 0)
    }

    @Test("each set field increments count by exactly one")
    func countTracksFields() {
        var draft = PendingKernelChanges()
        draft.chainType = .mainnet
        #expect(draft.count == 1)
        draft.workerThreadCount = 4
        #expect(draft.count == 2)
        draft.clearDataDirectoryOverride = true
        #expect(draft.count == 3)
        #expect(!draft.isEmpty)
    }

    // MARK: - Summary text

    @Test("summaryText is empty when no changes are pending")
    func summaryWhenEmpty() {
        #expect(PendingKernelChanges().summaryText.isEmpty)
    }

    @Test("summaryText uses singular copy for one pending change")
    func summarySingular() {
        var draft = PendingKernelChanges()
        draft.chainType = .signet
        #expect(draft.summaryText == "1 pending change — Apply will restart the kernel")
    }

    @Test("summaryText uses plural copy for multiple pending changes")
    func summaryPlural() {
        var draft = PendingKernelChanges()
        draft.chainType = .signet
        draft.workerThreadCount = 2
        #expect(draft.summaryText == "2 pending changes — Apply will restart the kernel")
    }
}

@Suite("PendingKernelChanges — apply(to:)")
@MainActor
struct PendingKernelChangesApplyTests {

    private func makeSettings() -> KernelAppSettings {
        let suite = "dev.21.PendingKernelChangesApplyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return KernelAppSettings(defaults: defaults)
    }

    // MARK: - Chain

    @Test("apply writes chainType when set, leaves other fields alone")
    func applyChainOnly() {
        let settings = makeSettings()
        settings.chainType = .regtest
        settings.workerThreadCount = 3

        var draft = PendingKernelChanges()
        draft.chainType = .signet
        draft.apply(to: settings)

        #expect(settings.chainType == .signet)
        #expect(settings.workerThreadCount == 3, "unchanged field must be preserved")
    }

    // MARK: - Worker threads

    @Test("apply writes workerThreadCount when set")
    func applyWorkerThreads() {
        let settings = makeSettings()
        settings.workerThreadCount = 1

        var draft = PendingKernelChanges()
        draft.workerThreadCount = 4
        draft.apply(to: settings)

        // Clamping may reduce the value to maxWorkerThreads, but it
        // must still be >= 1 (our starting point) for this assertion
        // to be meaningful on any test machine.
        #expect(settings.workerThreadCount > 1)
    }

    // MARK: - Data directory override

    @Test("apply clears dataDirectoryOverride when flagged")
    func applyClearsDataDir() {
        let settings = makeSettings()
        settings.dataDirectoryOverride = URL(fileURLWithPath: "/tmp/whatever")
        #expect(settings.dataDirectoryOverride != nil)

        var draft = PendingKernelChanges()
        draft.clearDataDirectoryOverride = true
        draft.apply(to: settings)

        #expect(settings.dataDirectoryOverride == nil)
    }

    @Test("apply leaves dataDirectoryOverride untouched when flag is false")
    func applyDoesNotClearWhenFlagOff() {
        let settings = makeSettings()
        let original = URL(fileURLWithPath: "/tmp/keep-me")
        settings.dataDirectoryOverride = original

        let draft = PendingKernelChanges()
        draft.apply(to: settings)

        #expect(settings.dataDirectoryOverride == original)
    }

    // MARK: - Combined

    @Test("apply writes every set field in one shot")
    func applyCombined() {
        let settings = makeSettings()
        settings.chainType = .regtest
        settings.workerThreadCount = 1
        settings.dataDirectoryOverride = URL(fileURLWithPath: "/tmp/old")

        var draft = PendingKernelChanges()
        draft.chainType = .signet
        draft.workerThreadCount = 2
        draft.clearDataDirectoryOverride = true
        draft.apply(to: settings)

        #expect(settings.chainType == .signet)
        #expect(settings.workerThreadCount >= 2)
        #expect(settings.dataDirectoryOverride == nil)
    }

    // MARK: - Idempotent no-op

    @Test("apply of an empty draft is a no-op")
    func applyEmptyIsNoOp() {
        let settings = makeSettings()
        settings.chainType = .testnet
        settings.workerThreadCount = 2
        let dir = URL(fileURLWithPath: "/tmp/preserve")
        settings.dataDirectoryOverride = dir

        let draft = PendingKernelChanges()
        draft.apply(to: settings)

        #expect(settings.chainType == .testnet)
        #expect(settings.workerThreadCount == 2)
        #expect(settings.dataDirectoryOverride == dir)
    }
}
