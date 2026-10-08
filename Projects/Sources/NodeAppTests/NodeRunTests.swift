//
//  NodeRunTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import Testing
@testable import NodeApp

// `NodeRun` and `NodeRunReport` exist only in phone and tablet builds — the
// same compile-time gate as the sources, so this whole suite is empty on a
// Mac build.
#if os(iOS)

/// Two baselines live beside each other: the observational `last_known_*` (the
/// sync poll writes it every 30 s while the node runs; the dashboard reads it)
/// and the run-owned `last_run_*` — the "blocks since last check" baseline,
/// which only a report actually returned as a result may move. These tests pin
/// the contract the actions rely on: a returned result updates the run
/// baseline always and the observational one unless it would rewind a fresher
/// same-chain reading, anything less updates neither, and the poll's writes
/// never touch the run baseline.
@Suite("Last-known tip persistence")
struct NodeRunTests {

    @MainActor
    @Test("a report carrying a measurement updates both baselines")
    func measuredReportPersists() {
        let defaults = makeVolatileDefaults()
        NodeViewModel.persistLastRun(height: 100, chain: "main", in: defaults)
        NodeViewModel.persistLastKnown(height: 100, chain: "main", in: defaults)
        let report = NodeRunReport(
            outcome: .started, syncResult: .notMeasured,
            chain: "main", blockHeight: 110, blocksGainedThisRun: nil,
            dialogTemplate: "Node running.")
        NodeRun.persistReportedTip(from: report, to: defaults)
        // A returned result is both the run baseline and a real observation.
        #expect(NodeViewModel.lastRun(in: defaults)?.height == 110)
        #expect(NodeViewModel.lastKnown(in: defaults)?.height == 110)
        #expect(NodeViewModel.lastRun(in: defaults)?.chain == "main")
    }

    @MainActor
    @Test("a run that measured nothing leaves both baselines alone")
    func unmeasuredReportDoesNotPersist() {
        // The paths the actions gate on all produce reports with no height —
        // cancelled, node-stopped, declined, timed out. Whatever the report
        // claims happened, absent fields mean nothing to write.
        let defaults = makeVolatileDefaults()
        NodeViewModel.persistLastRun(height: 100, chain: "main", in: defaults)
        NodeViewModel.persistLastKnown(height: 100, chain: "main", in: defaults)
        NodeRun.persistReportedTip(from: NodeRun.noAnswerReport(), to: defaults)
        NodeRun.persistReportedTip(
            from: NodeRunReport(
                outcome: .declined, syncResult: .notMeasured,
                chain: nil, blockHeight: nil, blocksGainedThisRun: nil,
                dialogTemplate: "The node did not start."),
            to: defaults)
        #expect(NodeViewModel.lastRun(in: defaults)?.height == 100)
        #expect(NodeViewModel.lastKnown(in: defaults)?.height == 100)
    }

    @MainActor
    @Test("a half-measured report does not persist — the baseline needs the pair")
    func halfMeasuredReportDoesNotPersist() {
        // Height without its chain is not a baseline: a tip means nothing
        // unless it says which chain it sits on, so the guard requires both.
        let defaults = makeVolatileDefaults()
        NodeViewModel.persistLastRun(height: 100, chain: "main", in: defaults)
        NodeRun.persistReportedTip(
            from: NodeRunReport(
                outcome: .started, syncResult: .notMeasured,
                chain: nil, blockHeight: 110, blocksGainedThisRun: nil,
                dialogTemplate: "Node running."),
            to: defaults)
        #expect(NodeViewModel.lastRun(in: defaults)?.height == 100)
        #expect(NodeViewModel.lastKnown(in: defaults) == nil)
    }

    @MainActor
    @Test("the poll's observational writes never move the run's baseline")
    func pollDoesNotAdvanceRunBaseline() {
        // The guarantee the key split exists for: `refreshSyncState` writes
        // `last_known_*` every 30 seconds while a node runs. If it also moved
        // `last_run_*`, "blocks since last check" would collapse toward zero
        // whenever the app had been alive recently.
        let defaults = makeVolatileDefaults()
        NodeViewModel.persistLastRun(height: 100, chain: "main", in: defaults)
        // What the poll does, twice over.
        NodeViewModel.persistLastKnown(height: 140, chain: "main", in: defaults)
        NodeViewModel.persistLastKnown(height: 150, chain: "main", in: defaults)
        #expect(NodeViewModel.lastKnown(in: defaults)?.height == 150)
        #expect(NodeViewModel.lastRun(in: defaults)?.height == 100)
    }

    @MainActor
    @Test("a returned tip older than the poll's latest does not rewind the dashboard")
    func staleTipDoesNotRewindObservational() {
        // The poll can write a newer height while the run asks its last
        // question — the report's reading is then seconds stale by the time
        // it is returned. `last_run_*` still records exactly what the run
        // reported; `last_known_*` keeps the fresher observation rather than
        // stepping the dashboard's "last validated" a block backward until
        // the next poll corrects it.
        let defaults = makeVolatileDefaults()
        NodeViewModel.persistLastKnown(height: 150, chain: "main", in: defaults)
        let report = NodeRunReport(
            outcome: .alreadyRunning, syncResult: .notMeasured,
            chain: "main", blockHeight: 140, blocksGainedThisRun: nil,
            dialogTemplate: "Node already running.")
        NodeRun.persistReportedTip(from: report, to: defaults)
        #expect(NodeViewModel.lastKnown(in: defaults)?.height == 150)
        // The run-owned baseline records what was reported — unconditionally.
        #expect(NodeViewModel.lastRun(in: defaults)?.height == 140)
    }

    @MainActor
    @Test("a chain-switch report updates the observational store even at a lower height")
    func chainSwitchStillUpdatesObservational() {
        // The rewind guard compares tips on the *same* chain only: after a
        // main→signet switch, "last validated" must follow the node to the
        // new chain rather than stay stuck on a taller mainnet tip forever.
        let defaults = makeVolatileDefaults()
        NodeViewModel.persistLastKnown(height: 800_000, chain: "main", in: defaults)
        let report = NodeRunReport(
            outcome: .alreadyRunning, syncResult: .notMeasured,
            chain: "signet", blockHeight: 5, blocksGainedThisRun: nil,
            dialogTemplate: "Node already running.")
        NodeRun.persistReportedTip(from: report, to: defaults)
        #expect(NodeViewModel.lastKnown(in: defaults)?.chain == "signet")
        #expect(NodeViewModel.lastKnown(in: defaults)?.height == 5)
        #expect(NodeViewModel.lastRun(in: defaults)?.chain == "signet")
    }
}

#endif
