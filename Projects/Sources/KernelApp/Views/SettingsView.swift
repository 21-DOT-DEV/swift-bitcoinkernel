//
//  SettingsView.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2022-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

//  In-app Settings surface. Two-tier apply model per Apple HIG:
//
//  - Immediate-apply fields (live-bound to KernelAppSettings):
//      block-source endpoint + preset, Tor routing toggle, logging
//      master switch, log level. Changes fire
//      `applySettingsChange()` directly.
//
//  - Draft-then-Apply fields (staged in PendingKernelChanges):
//      chainType, workerThreadCount, dataDirectoryOverride reset.
//      These cost a full kernel rebuild, so we batch them behind
//      a persistent banner with Apply + Revert.
//
//  Reindex is intentionally NOT here — lives on the Sync tab as an
//  action, not a setting.

import BitcoinKernel
import Foundation
import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @Bindable var viewModel: KernelAppViewModel
    @Bindable var settings: KernelAppSettings
    @Bindable var tor: TorViewModel

    /// Staged kernel-restart changes. Empty → banner hidden.
    @State private var draft = PendingKernelChanges()

    /// Custom URL text-field state when the user selects the
    /// ``EndpointSelection/custom`` preset. Kept in view state so
    /// partial typing doesn't repeatedly respawn the sync task.
    @State private var customEndpointText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            if !draft.isEmpty {
                pendingBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Form {
                networkSection
                chainSection
                advancedSection
                loggingSection
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
        }
        .animation(.default, value: draft)
        .onAppear { syncCustomEndpointText() }
    }

    // MARK: - Banner

    private var pendingBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(draft.summaryText)
                .font(.callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Revert", role: .cancel) {
                draft = PendingKernelChanges()
            }
            .buttonStyle(.bordered)

            Button("Apply") {
                Task { await applyDraft() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.syncTask != nil)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
    }

    // MARK: - Network section (immediate-apply)

    private var networkSection: some View {
        Section {
            Picker("Block Source", selection: endpointSelectionBinding) {
                ForEach(
                    BlockSourcePreset.presets(
                        for: effectiveChainType,
                        torRouting: settings.routeDownloadsThroughTor
                    ),
                    id: \.self
                ) { preset in
                    Text(preset.displayName).tag(EndpointSelection.preset(preset))
                }
                Text("Custom URL").tag(EndpointSelection.custom)
                Text("None").tag(EndpointSelection.none)
            }
            .disabled(draft.chainType != nil)

            if case .custom = currentEndpointSelection {
                TextField("https://...", text: $customEndpointText)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .autocorrectionDisabled()
                    .disabled(draft.chainType != nil)
                    .onSubmit { commitCustomEndpoint() }

                Button("Use this URL") { commitCustomEndpoint() }
                    .disabled(draft.chainType != nil || customEndpointText.isEmpty)
            }

            Toggle("Route block downloads through Tor", isOn: Binding(
                get: { settings.routeDownloadsThroughTor },
                set: { newValue in
                    settings.routeDownloadsThroughTor = newValue
                    // Mirror the toggle onto the Tor client's lifecycle
                    // so we don't pay the battery/CPU cost of Tor when
                    // the user isn't routing through it.
                    if newValue {
                        tor.start()
                    } else {
                        tor.stop()
                    }
                    Task { await viewModel.applySettingsChange() }
                }
            ))

            if settings.routeDownloadsThroughTor {
                TorStatusView(viewModel: tor)
            }
        } header: {
            Text("Network")
        } footer: {
            if draft.chainType != nil {
                Text("Block source locked while a chain change is pending. Apply or Revert to continue.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if settings.routeDownloadsThroughTor {
                Text("Block-source requests will wait for Tor to finish bootstrapping before syncing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Chain section (draft)

    private var chainSection: some View {
        Section {
            Picker("Chain", selection: chainSelectionBinding) {
                Text("Mainnet").tag(ChainType.mainnet)
                Text("Testnet3").tag(ChainType.testnet)
                Text("Testnet4").tag(ChainType.testnet4)
                Text("Signet").tag(ChainType.signet)
                Text("Regtest").tag(ChainType.regtest)
            }
        } header: {
            Text("Chain")
        } footer: {
            Text("Changing the chain restarts the kernel against a different network's data directory.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Advanced section (draft)

    private var advancedSection: some View {
        Section {
            Stepper(
                value: workerThreadsBinding,
                in: 0...Int(settings.maxWorkerThreads)
            ) {
                LabeledContent(
                    "Worker Threads",
                    value: effectiveWorkerThreads == 0
                        ? "Auto-detect"
                        : "\(effectiveWorkerThreads)"
                )
            }

            LabeledContent("Data Directory") {
                Text(settings.effectiveDataDirectory.path)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }

            if settings.dataDirectoryOverride != nil || draft.clearDataDirectoryOverride {
                Button("Reset to Default Location", role: .destructive) {
                    draft.clearDataDirectoryOverride.toggle()
                }
            }
        } header: {
            Text("Advanced")
        } footer: {
            Text("Custom data-directory selection arrives in a later release.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Logging section (immediate-apply, minimal)

    private var loggingSection: some View {
        Section {
            Toggle("Enable logging", isOn: $settings.loggingEnabled)

            Picker("Log Level", selection: $settings.logLevel) {
                ForEach(LogLevel.allCases, id: \.self) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .disabled(!settings.loggingEnabled)
        } header: {
            Text("Logging")
        } footer: {
            Text("Log categories and formatting controls arrive in a later release.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Apply / revert

    private func applyDraft() async {
        draft.apply(to: settings)
        await viewModel.applySettingsChange()
        draft = PendingKernelChanges()
        syncCustomEndpointText()
    }

    // MARK: - Binding helpers

    private var effectiveChainType: ChainType {
        draft.chainType ?? settings.chainType
    }

    private var effectiveWorkerThreads: Int32 {
        draft.workerThreadCount ?? settings.workerThreadCount
    }

    private var chainSelectionBinding: Binding<ChainType> {
        Binding(
            get: { effectiveChainType },
            set: { newValue in
                // Pick-back-to-current clears the draft rather than
                // leaving a no-op staged.
                if newValue == settings.chainType {
                    draft.chainType = nil
                } else {
                    draft.chainType = newValue
                }
            }
        )
    }

    private var workerThreadsBinding: Binding<Int> {
        Binding(
            get: { Int(effectiveWorkerThreads) },
            set: { newValue in
                let int32 = Int32(clamping: newValue)
                if int32 == settings.workerThreadCount {
                    draft.workerThreadCount = nil
                } else {
                    draft.workerThreadCount = int32
                }
            }
        )
    }

    // MARK: - Endpoint plumbing

    /// The current selection state derived from `settings.blockSourceEndpoint`.
    private var currentEndpointSelection: EndpointSelection {
        guard let endpoint = settings.blockSourceEndpoint else { return .none }
        if let preset = BlockSourcePreset.allCases.first(where: { $0.url == endpoint }) {
            return .preset(preset)
        }
        return .custom
    }

    /// Three-way selection for the endpoint Picker: a known preset, a
    /// user-entered custom URL, or no selection at all (empty state).
    enum EndpointSelection: Hashable {
        case preset(BlockSourcePreset)
        case custom
        case none
    }

    private var endpointSelectionBinding: Binding<EndpointSelection> {
        Binding(
            get: { currentEndpointSelection },
            set: { newValue in
                switch newValue {
                case .preset(let preset):
                    settings.blockSourceEndpoint = preset.url
                    customEndpointText = preset.url.absoluteString
                    Task { await viewModel.applySettingsChange() }
                case .custom:
                    // Await commitCustomEndpoint() to actually write; the
                    // field appears via `currentEndpointSelection` inspection.
                    customEndpointText = settings.blockSourceEndpoint?.absoluteString ?? ""
                case .none:
                    settings.blockSourceEndpoint = nil
                    Task { await viewModel.applySettingsChange() }
                }
            }
        )
    }

    private func commitCustomEndpoint() {
        let trimmed = customEndpointText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else { return }
        settings.blockSourceEndpoint = url
        Task { await viewModel.applySettingsChange() }
    }

    private func syncCustomEndpointText() {
        customEndpointText = settings.blockSourceEndpoint?.absoluteString ?? ""
    }
}

// MARK: - LogLevel display

private extension LogLevel {
    /// Human-friendly label for the Picker. `rawValue` ordering matches
    /// severity, but the enum names are lowercase C-style identifiers.
    var displayName: String {
        String(describing: self).capitalized
    }
}
