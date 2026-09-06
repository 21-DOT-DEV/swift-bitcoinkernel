//
//  DashboardView.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import SwiftUI

/// Operator dashboard for the embedded node: chain tip, sync progress, peers,
/// mempool, and storage. Polls the typed `RPCClient` every few seconds while
/// the node is running and the app is foregrounded.
struct DashboardView: View {
    @Bindable var nodeViewModel: NodeViewModel
    var torViewModel: TorViewModel
    var viewModel: DashboardViewModel
    var buildArguments: () -> [String] = { [] }

    @Environment(\.scenePhase) private var scenePhase

    private struct PollKey: Equatable {
        let running: Bool
        let phase: ScenePhase
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Dashboard")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        NodeToolbarMenu(
                            nodeViewModel: nodeViewModel,
                            torViewModel: torViewModel,
                            buildArguments: buildArguments
                        )
                    }
                }
        }
        .task(id: PollKey(running: nodeViewModel.isRunning, phase: scenePhase)) {
            guard nodeViewModel.isRunning, scenePhase == .active else { return }
            while !Task.isCancelled {
                await viewModel.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !nodeViewModel.isRunning {
            ContentUnavailableView {
                Label("Node Not Running", systemImage: "gauge.medium")
            } description: {
                if let last = NodeViewModel.lastKnown {
                    Text("Last validated block \(last.height) on \(last.chain). Start the node to resume.")
                } else {
                    Text("Start the node to watch its chain tip, peers, mempool, and storage.")
                }
            }
        } else if viewModel.chain == nil {
            if let error = viewModel.lastError {
                ContentUnavailableView {
                    Label("Waiting for RPC", systemImage: "antenna.radiowaves.left.and.right.slash")
                } description: {
                    Text(error).font(.caption).monospaced()
                }
            } else {
                ProgressView("Connecting…")
            }
        } else {
            List {
                chainSection
                syncSection
                peersSection
                mempoolSection
                storageSection
                footerSection
            }
        }
    }

    @ViewBuilder
    private var chainSection: some View {
        if let chain = viewModel.chain {
            Section("Chain Tip") {
                LabeledContent("Network", value: chain.chain)
                LabeledContent("Height") { Text(chain.height, format: .number) }
                LabeledContent("Best block") {
                    Text("\(chain.bestBlockHash.prefix(16))…")
                        .monospaced().font(.caption)
                }
                LabeledContent("Tip age") { Text(chain.tipTime, style: .relative) }
            }
        }
    }

    @ViewBuilder
    private var syncSection: some View {
        if let sync = viewModel.sync {
            Section("Sync") {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: sync.verificationProgress)
                    LabeledContent("Verification") {
                        Text(sync.verificationProgress, format: .percent.precision(.fractionLength(2)))
                    }
                }
                if sync.isInitialBlockDownload {
                    LabeledContent("Blocks / Headers", value: "\(sync.blocks) / \(sync.headers)")
                    if sync.headersAhead > 0 {
                        LabeledContent("Headers ahead") { Text(sync.headersAhead, format: .number) }
                    }
                    Label("Initial block download", systemImage: "arrow.down.circle")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("Synced to tip", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.green)
                }
            }
        }
    }

    @ViewBuilder
    private var peersSection: some View {
        if let peers = viewModel.peers {
            Section("Peers") {
                LabeledContent("Connected") { Text(peers.total, format: .number) }
                LabeledContent("Direction", value: "\(peers.outbound) out · \(peers.inbound) in")
                LabeledContent("Transport", value: "\(peers.clearnet) clearnet · \(peers.onion) onion")
                if !peers.rows.isEmpty {
                    NavigationLink("View peers") { PeerListView(rows: peers.rows) }
                }
            }
        }
    }

    @ViewBuilder
    private var mempoolSection: some View {
        if let mempool = viewModel.mempool {
            Section("Mempool") {
                LabeledContent("Transactions") { Text(mempool.count, format: .number) }
                LabeledContent("Virtual size", value: Self.bytes(mempool.vsizeBytes))
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: mempool.usageFraction)
                    LabeledContent("Memory",
                        value: "\(Self.bytes(mempool.usageBytes)) / \(Self.bytes(mempool.maxBytes))")
                }
                LabeledContent("Min relay fee") {
                    Text("\(mempool.minFeeSatPerVByte, format: .number.precision(.fractionLength(2))) sat/vB")
                }
            }
        }
    }

    @ViewBuilder
    private var storageSection: some View {
        if let storage = viewModel.storage {
            Section("Storage") {
                LabeledContent("Block data", value: Self.bytes(storage.sizeOnDiskBytes))
                if storage.pruned {
                    LabeledContent("Mode", value: "Pruned")
                    if let target = storage.pruneTargetBytes {
                        LabeledContent("Prune target", value: Self.bytes(target))
                    }
                } else {
                    LabeledContent("Mode", value: "Archival")
                }
            }
        }
    }

    @ViewBuilder
    private var footerSection: some View {
        Section {
            if let updated = viewModel.lastUpdated {
                LabeledContent("Updated") { Text(updated, style: .relative) }
            }
            if let error = viewModel.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}

// MARK: - Peer drill-in

private struct PeerListView: View {
    let rows: [PeerRow]

    var body: some View {
        List(rows) { row in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(row.addr).monospaced().font(.callout).lineLimit(1)
                    Spacer()
                    Image(systemName: row.inbound ? "arrow.down.left" : "arrow.up.right")
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Text(row.network)
                    Text(row.transport)
                    Text(row.connectionType)
                    if let ping = row.pingMilliseconds {
                        Text("\(ping, format: .number.precision(.fractionLength(0))) ms")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                Text(row.subver).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .navigationTitle("Peers")
    }
}
