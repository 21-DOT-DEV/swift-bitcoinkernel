//
//  SyncSnapshotTests.swift
//  21-DOT-DEV/Bitcoin
//
//  Drives the design of SyncSnapshot — the @Observable view-model
//  state struct used by KernelAppViewModel.
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

@Suite("SyncSnapshot")
struct SyncSnapshotTests {

    // MARK: - Idle factory

    @Test("idle has phase .idle, zero heights, and the canonical status text")
    func idleFactoryDefaults() {
        let snapshot = SyncSnapshot.idle

        #expect(snapshot.phase == .idle)
        #expect(snapshot.statusText == "Idle")
        #expect(snapshot.localHeight == 0)
        #expect(snapshot.remoteHeight == 0)
        #expect(snapshot.tipHash.isEmpty)
        #expect(snapshot.verificationProgress == 0.0)
    }

    // MARK: - Update → Snapshot translation

    @Test("init(from:) translates .preparing")
    func initFromPreparingUpdate() {
        let tip = BlockTip(hash: Data(repeating: 0xAA, count: 32), height: 0)
        let remote = BlockTip(hash: Data(repeating: 0xBB, count: 32), height: 100)
        let update = BlockchainSync.Update(state: .preparing, tip: tip, remoteTip: remote)

        let snapshot = SyncSnapshot(from: update)

        #expect(snapshot.phase == .preparing)
        #expect(snapshot.statusText == "Preparing")
        #expect(snapshot.localHeight == 0)
        #expect(snapshot.remoteHeight == 100)
        #expect(snapshot.tipHash == tip.hash)
        #expect(snapshot.verificationProgress == 0.0)
    }

    @Test("init(from:) translates .syncing — status reports progress")
    func initFromSyncingUpdate() {
        let tip = BlockTip(hash: Data(repeating: 0xAA, count: 32), height: 25)
        let remote = BlockTip(hash: Data(repeating: 0xBB, count: 32), height: 100)
        let update = BlockchainSync.Update(state: .syncing, tip: tip, remoteTip: remote)

        let snapshot = SyncSnapshot(from: update)

        #expect(snapshot.phase == .syncing)
        #expect(snapshot.statusText == "Validated block 25 of 100")
        #expect(snapshot.localHeight == 25)
        #expect(snapshot.remoteHeight == 100)
        #expect(snapshot.tipHash == tip.hash)
        #expect(snapshot.verificationProgress == 0.25)
    }

    @Test("init(from:) translates .finished")
    func initFromFinishedUpdate() {
        let tip = BlockTip(hash: Data(repeating: 0xAA, count: 32), height: 100)
        let remote = BlockTip(hash: Data(repeating: 0xAA, count: 32), height: 100)
        let update = BlockchainSync.Update(state: .finished, tip: tip, remoteTip: remote)

        let snapshot = SyncSnapshot(from: update)

        #expect(snapshot.phase == .finished)
        #expect(snapshot.statusText == "Sync complete")
        #expect(snapshot.localHeight == 100)
        #expect(snapshot.remoteHeight == 100)
        #expect(snapshot.verificationProgress == 1.0)
    }

    @Test("init(from:) translates .failed and preserves the reason")
    func initFromFailedUpdate() {
        let tip = BlockTip(hash: Data(repeating: 0xAA, count: 32), height: 5)
        let remote = BlockTip(hash: Data(repeating: 0xBB, count: 32), height: 100)
        let update = BlockchainSync.Update(
            state: .failed("network unavailable"),
            tip: tip,
            remoteTip: remote
        )

        let snapshot = SyncSnapshot(from: update)

        #expect(snapshot.phase == .failed("network unavailable"))
        #expect(snapshot.statusText == "Sync failed: network unavailable")
        #expect(snapshot.localHeight == 5)
        #expect(snapshot.remoteHeight == 100)
    }

    // MARK: - Phase.isActive

    @Test("Phase.isActive is true for waitingForTor, preparing, and syncing")
    func phaseIsActiveOnlyDuringActiveStates() {
        #expect(!SyncSnapshot.Phase.idle.isActive)
        #expect(SyncSnapshot.Phase.waitingForTor.isActive)
        #expect(SyncSnapshot.Phase.preparing.isActive)
        #expect(SyncSnapshot.Phase.syncing.isActive)
        #expect(!SyncSnapshot.Phase.finished.isActive)
        #expect(!SyncSnapshot.Phase.failed("any").isActive)
    }
}
