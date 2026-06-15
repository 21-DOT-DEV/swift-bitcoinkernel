//
//  SyncView.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2022-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

//  The main kernel-sync surface. Wires KernelAppViewModel snapshot
//  + lifecycle controls to a SwiftUI tree, including the destructive
//  reindex actions gated behind a confirmation dialog.
//
//  Display logic lives in a pure value-type Presenter below, so the
//  SwiftUI tree can stay thin and most behavioural coverage can be
//  expressed as value assertions.

import BitcoinKernel
import Foundation
import SwiftUI

// MARK: - SyncView

struct SyncView: View {
    @Bindable var viewModel: KernelAppViewModel
    @Bindable var settings: KernelAppSettings
    @Binding var selectedTab: RootView.Tab

    /// Non-nil while the reindex confirmation dialog is visible. Drives
    /// the `.confirmationDialog` binding and carries which mode the user
    /// tapped through to the confirmed action handler.
    @State private var pendingReindexMode: ReindexMode?

    private var presenter: Presenter {
        Presenter(
            snapshot: viewModel.snapshot,
            chainType: settings.chainType,
            hasEndpoint: settings.blockSourceEndpoint != nil,
            isRunning: viewModel.syncTask != nil
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(presenter.title)
                .font(.title.bold())

            if presenter.needsEndpointSelection {
                endpointEmptyState
            } else {
                syncContent
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(
            pendingReindexMode?.confirmationTitle ?? "Reindex",
            isPresented: Binding(
                get: { pendingReindexMode != nil },
                set: { isPresented in
                    if !isPresented { pendingReindexMode = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            if let mode = pendingReindexMode {
                Button(mode.confirmationTitle, role: .destructive) {
                    Task { await viewModel.requestReindex(mode) }
                    pendingReindexMode = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingReindexMode = nil }
        } message: {
            Text(pendingReindexMode?.confirmationMessage ?? "")
        }
    }

    // MARK: - Empty state

    private var endpointEmptyState: some View {
        ContentUnavailableView {
            Label("No Block Source Selected", systemImage: "network.slash")
        } description: {
            Text("Choose a block source in Settings to begin syncing.")
        } actions: {
            Button("Open Settings") {
                selectedTab = .settings
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Main sync content

    private var syncContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Progress bar.
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * viewModel.snapshot.verificationProgress)
                }
            }
            .frame(height: 6)

            LabeledContent("Progress", value: presenter.progressLabel)
            LabeledContent("Height", value: presenter.heightLabel)

            ViewThatFits {
                LabeledContent {
                    tipHashText
                } label: {
                    Text("Tip Hash")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Tip Hash")
                    tipHashText
                }
            }

            if let reason = presenter.failureReason {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Text(presenter.statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()

            sourceCard

            Spacer()

            Divider()

            HStack(spacing: 12) {
                Button(presenter.lifecycleButtonTitle) {
                    Task { await toggleLifecycle() }
                }
                .disabled(presenter.lifecycleButtonIsDisabled)
                .keyboardShortcut("r", modifiers: .command)

                Spacer()
            }

            Divider()

            dangerousSection
        }
    }

    // MARK: - Dangerous section

    private var dangerousSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dangerous")
                .font(.headline)
                .foregroundStyle(.red)

            Text("These actions tear down the kernel and rebuild local validation state from the stored block files.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Reindex Chainstate", role: .destructive) {
                    pendingReindexMode = .chainstate
                }
                .disabled(!presenter.dangerousActionsAreEnabled)

                Button("Full Reindex", role: .destructive) {
                    pendingReindexMode = .full
                }
                .disabled(!presenter.dangerousActionsAreEnabled)
            }
        }
    }

    // MARK: - Helpers

    private var tipHashText: some View {
        Text(presenter.tipHashLabel)
            .font(.callout.monospaced())
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .allowsTightening(true)
    }

    private func toggleLifecycle() async {
        if viewModel.syncTask == nil {
            await viewModel.start()
        } else {
            await viewModel.stop()
        }
    }

    // MARK: - Source card

    /// Block-source health, scoped honestly to what the kernel is: a block
    /// validator fed over HTTP, with no peer set and no mempool.
    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Source")
                .font(.headline)

            LabeledContent("Block source", value: sourceName)
            LabeledContent("Tor routing", value: settings.routeDownloadsThroughTor ? "On" : "Off")
            if let rate = viewModel.blocksPerSecond {
                LabeledContent("Rate", value: String(format: "%.1f blocks/s", rate))
            }
            if let updated = viewModel.lastSyncUpdate {
                LabeledContent("Updated") { Text(updated, style: .relative) }
            }
            LabeledContent("Footprint", value: footprintText)

            Text("Validation only: no peers or mempool. Blocks come from the source above and are validated by libbitcoinkernel. For a peer-to-peer node with a mempool, use NodeApp.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .task(id: settings.effectiveDataDirectory) {
            while !Task.isCancelled {
                await viewModel.refreshDataDirectorySize()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private var sourceName: String {
        guard let endpoint = settings.blockSourceEndpoint else { return "—" }
        return BlockSourcePreset.allCases.first { $0.url == endpoint }?.displayName
            ?? endpoint.host() ?? endpoint.absoluteString
    }

    private var footprintText: String {
        guard let size = viewModel.dataDirectorySize else { return "Measuring…" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

// MARK: - Presenter

extension SyncView {
    /// Pure value type holding the display-layer transformations of a
    /// ``SyncSnapshot``. Test target imports it via `@testable` and
    /// exercises every branch without running SwiftUI.
    struct Presenter: Equatable {
        let snapshot: SyncSnapshot
        let chainType: ChainType
        let hasEndpoint: Bool
        let isRunning: Bool

        var title: String {
            "\(chainType.description.capitalized) Kernel Sync"
        }

        var progressLabel: String {
            String(format: "%.1f%%", snapshot.verificationProgress * 100)
        }

        var heightLabel: String {
            "\(snapshot.localHeight) / \(snapshot.remoteHeight)"
        }

        var tipHashLabel: String {
            guard !snapshot.tipHash.isEmpty else { return "Unavailable" }
            return snapshot.tipHash.map { String(format: "%02x", $0) }.joined()
        }

        var statusText: String { snapshot.statusText }

        var failureReason: String? {
            if case .failed(let reason) = snapshot.phase {
                return reason
            }
            return nil
        }

        var needsEndpointSelection: Bool { !hasEndpoint }

        var lifecycleButtonTitle: String {
            isRunning ? "Stop" : "Start"
        }

        var lifecycleButtonIsDisabled: Bool { !hasEndpoint }

        /// Whether the Dangerous section's reindex buttons should be
        /// enabled. Reindexing requires a kernel teardown + rebuild, so
        /// it's only offered when the view model is idle (not actively
        /// running) and an endpoint is configured.
        var dangerousActionsAreEnabled: Bool {
            hasEndpoint && !isRunning
        }
    }
}
