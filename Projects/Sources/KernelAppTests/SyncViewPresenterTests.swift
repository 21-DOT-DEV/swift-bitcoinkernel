//
//  SyncViewPresenterTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2022-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

//  Drives the display-logic layer of SyncView. Pure tests — the
//  presenter is a value type that consumes a SyncSnapshot plus a
//  couple of context flags and produces the strings / booleans the
//  view binds to, so the SwiftUI tree itself needs no runtime
//  inspection to get solid coverage.

import BitcoinKernel
import Foundation
import Testing
@testable import KernelApp

@Suite("SyncView.Presenter")
struct SyncViewPresenterTests {

    private func snapshot(
        phase: SyncSnapshot.Phase = .idle,
        status: String = "Idle",
        local: Int = 0,
        remote: Int = 0,
        hash: Data = Data(),
        progress: Double = 0
    ) -> SyncSnapshot {
        SyncSnapshot(
            phase: phase,
            statusText: status,
            localHeight: local,
            remoteHeight: remote,
            tipHash: hash,
            verificationProgress: progress
        )
    }

    // MARK: - Title

    @Test("title reflects the selected chain")
    func titleReflectsChain() {
        let p = SyncView.Presenter(
            snapshot: snapshot(),
            chainType: .signet,
            hasEndpoint: true,
            isRunning: false
        )
        #expect(p.title == "Signet Kernel Sync")
    }

    @Test("title capitalises mainnet correctly")
    func titleHandlesMainnet() {
        let p = SyncView.Presenter(
            snapshot: snapshot(),
            chainType: .mainnet,
            hasEndpoint: true,
            isRunning: false
        )
        #expect(p.title == "Mainnet Kernel Sync")
    }

    // MARK: - Progress label

    @Test("progress label formats to one decimal percent")
    func progressLabelFormatting() {
        let p = SyncView.Presenter(
            snapshot: snapshot(progress: 0.256),
            chainType: .regtest,
            hasEndpoint: true,
            isRunning: true
        )
        #expect(p.progressLabel == "25.6%")
    }

    @Test("progress label at zero is 0.0%")
    func progressLabelZero() {
        let p = SyncView.Presenter(
            snapshot: snapshot(progress: 0),
            chainType: .regtest,
            hasEndpoint: true,
            isRunning: false
        )
        #expect(p.progressLabel == "0.0%")
    }

    @Test("progress label at one is 100.0%")
    func progressLabelFull() {
        let p = SyncView.Presenter(
            snapshot: snapshot(progress: 1),
            chainType: .regtest,
            hasEndpoint: true,
            isRunning: false
        )
        #expect(p.progressLabel == "100.0%")
    }

    // MARK: - Height label

    @Test("height label formats as local / remote")
    func heightLabel() {
        let p = SyncView.Presenter(
            snapshot: snapshot(local: 25, remote: 100),
            chainType: .regtest,
            hasEndpoint: true,
            isRunning: true
        )
        #expect(p.heightLabel == "25 / 100")
    }

    // MARK: - Tip hash label

    @Test("tipHashLabel returns 'Unavailable' when empty")
    func tipHashEmpty() {
        let p = SyncView.Presenter(
            snapshot: snapshot(hash: Data()),
            chainType: .regtest,
            hasEndpoint: true,
            isRunning: false
        )
        #expect(p.tipHashLabel == "Unavailable")
    }

    @Test("tipHashLabel renders a non-empty hash as lowercase hex")
    func tipHashRendered() {
        let bytes = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let p = SyncView.Presenter(
            snapshot: snapshot(hash: bytes),
            chainType: .regtest,
            hasEndpoint: true,
            isRunning: true
        )
        #expect(p.tipHashLabel == "deadbeef")
    }

    // MARK: - Failure reason

    @Test("failureReason is nil on non-failed phases")
    func failureReasonNil() {
        for phase: SyncSnapshot.Phase in [.idle, .preparing, .syncing, .finished] {
            let p = SyncView.Presenter(
                snapshot: snapshot(phase: phase),
                chainType: .regtest,
                hasEndpoint: true,
                isRunning: phase.isActive
            )
            #expect(p.failureReason == nil, "phase \(phase) should have no failure reason")
        }
    }

    @Test("failureReason extracts the reason from .failed")
    func failureReasonExtraction() {
        let p = SyncView.Presenter(
            snapshot: snapshot(phase: .failed("network down"), status: "Sync failed: network down"),
            chainType: .regtest,
            hasEndpoint: true,
            isRunning: false
        )
        #expect(p.failureReason == "network down")
    }

    // MARK: - Empty state

    @Test("needsEndpointSelection is true when no block source is selected")
    func needsEndpointSelectionWhenAbsent() {
        let p = SyncView.Presenter(
            snapshot: snapshot(),
            chainType: .regtest,
            hasEndpoint: false,
            isRunning: false
        )
        #expect(p.needsEndpointSelection)
    }

    @Test("needsEndpointSelection is false once an endpoint is set")
    func needsEndpointSelectionFalseWhenPresent() {
        let p = SyncView.Presenter(
            snapshot: snapshot(),
            chainType: .regtest,
            hasEndpoint: true,
            isRunning: false
        )
        #expect(!p.needsEndpointSelection)
    }

    // MARK: - Start/stop button

    @Test("lifecycleButtonTitle reads 'Start' when idle")
    func lifecycleButtonStart() {
        let p = SyncView.Presenter(
            snapshot: snapshot(phase: .idle),
            chainType: .regtest,
            hasEndpoint: true,
            isRunning: false
        )
        #expect(p.lifecycleButtonTitle == "Start")
    }

    @Test("lifecycleButtonTitle reads 'Stop' while a run is active")
    func lifecycleButtonStop() {
        let p = SyncView.Presenter(
            snapshot: snapshot(phase: .syncing),
            chainType: .regtest,
            hasEndpoint: true,
            isRunning: true
        )
        #expect(p.lifecycleButtonTitle == "Stop")
    }

    @Test("lifecycleButtonIsDisabled mirrors the empty-state condition")
    func lifecycleButtonDisabled() {
        // No endpoint → button disabled, regardless of phase.
        let noEndpoint = SyncView.Presenter(
            snapshot: snapshot(),
            chainType: .regtest,
            hasEndpoint: false,
            isRunning: false
        )
        #expect(noEndpoint.lifecycleButtonIsDisabled)

        // Endpoint present → button enabled.
        let withEndpoint = SyncView.Presenter(
            snapshot: snapshot(),
            chainType: .regtest,
            hasEndpoint: true,
            isRunning: false
        )
        #expect(!withEndpoint.lifecycleButtonIsDisabled)
    }

    // MARK: - Dangerous section

    @Test("dangerousActionsAreEnabled is false while a sync run is active")
    func dangerousActionsDisabledWhileRunning() {
        let running = SyncView.Presenter(
            snapshot: snapshot(phase: .syncing),
            chainType: .regtest,
            hasEndpoint: true,
            isRunning: true
        )
        #expect(!running.dangerousActionsAreEnabled)
    }

    @Test("dangerousActionsAreEnabled is false when no endpoint is configured")
    func dangerousActionsDisabledWithoutEndpoint() {
        let noEndpoint = SyncView.Presenter(
            snapshot: snapshot(),
            chainType: .regtest,
            hasEndpoint: false,
            isRunning: false
        )
        #expect(!noEndpoint.dangerousActionsAreEnabled)
    }

    @Test("dangerousActionsAreEnabled is true when idle and endpoint present")
    func dangerousActionsEnabledWhenReady() {
        let ready = SyncView.Presenter(
            snapshot: snapshot(phase: .idle),
            chainType: .regtest,
            hasEndpoint: true,
            isRunning: false
        )
        #expect(ready.dangerousActionsAreEnabled)
    }
}
