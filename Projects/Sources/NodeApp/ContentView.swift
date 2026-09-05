//
//  ContentView.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2022-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import SwiftUI
import Bitcoin

enum AppTab: String, Hashable {
    case dashboard = "Dashboard"
    case commands = "Commands"
    case configuration = "Configuration"
    case logs = "Logs"
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .dashboard
    // Owned by the process, not by this screen, so a background-launched action can
    // reach them when no interface exists. Everything below reads them exactly as it
    // did when they were created here.
    private var nodeViewModel: NodeViewModel { NodeSession.shared.node }
    private var torViewModel: TorViewModel { NodeSession.shared.tor }
    @State private var commandsViewModel = CommandsViewModel()
    @State private var dashboardViewModel = DashboardViewModel(
        source: RPCClient(url: InternalRPC.url, cookieFile: InternalRPC.cookieFileURL)
    )

    @AppStorage("keep_screen_awake") private var keepScreenAwake = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Dashboard", systemImage: "gauge.medium", value: .dashboard) {
                DashboardView(
                    nodeViewModel: nodeViewModel,
                    torViewModel: torViewModel,
                    viewModel: dashboardViewModel,
                    buildArguments: { DaemonConfig.buildArguments(torProxy: torViewModel.proxyAddress) }
                )
            }

            Tab("Commands", systemImage: "terminal", value: .commands) {
                CommandsView(
                    viewModel: commandsViewModel,
                    nodeViewModel: nodeViewModel,
                    torViewModel: torViewModel,
                    buildArguments: { DaemonConfig.buildArguments(torProxy: torViewModel.proxyAddress) }
                )
            }

            Tab("Configuration", systemImage: "gearshape.2", value: .configuration) {
                ConfigurationView(nodeViewModel: nodeViewModel, torViewModel: torViewModel)
            }

            Tab("Logs", systemImage: "doc.text", value: .logs) {
                LogView()
            }
        }
        .task {
            NodeDiagnostics.snapshot("app-launch")
            if UserDefaults.standard.bool(forKey: "tor_enabled") {
                torViewModel.start()
            }
        }
        .keepScreenAwake(keepScreenAwake)
    }
}

// MARK: - Node Toolbar Menu

struct NodeToolbarMenu: View {
    @Bindable var nodeViewModel: NodeViewModel
    var torViewModel: TorViewModel
    var buildArguments: () -> [String] = { [] }

    @AppStorage("tor_enabled") private var torEnabled = false

    /// `false` when Tor is enabled but not yet bootstrapped. Prevents the
    /// daemon from launching without a proxy when the user expects Tor.
    private var canStartNode: Bool {
        !torEnabled || torViewModel.isReady
    }

    var body: some View {
        Menu {
            Section {
                Label(nodeViewModel.nodeState.rawValue, systemImage: statusSymbol)
            }

            if torViewModel.displayState != .disabled {
                Section {
                    Label(torStatusLabel, systemImage: torStatusSymbol)
                }
            }

            if nodeViewModel.nodeState == .stopped {
                Button {
                    startNode()
                } label: {
                    Label("Start Node", systemImage: "play.fill")
                }
                .disabled(!canStartNode)

                if !canStartNode {
                    Label("Waiting for Tor to bootstrap", systemImage: "hourglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if nodeViewModel.nodeState == .running {
                Button(role: .destructive) {
                    stopNode()
                } label: {
                    Label("Stop Node", systemImage: "stop.fill")
                }
            }
        } label: {
            Image(systemName: statusSymbol)
                .symbolRenderingMode(.palette)
                .foregroundStyle(statusColor)
        }
    }

    private func startNode() {
        let socksPort = torEnabled ? torViewModel.socksEndpoint.map { UInt16(clamping: $0.port) } : nil
        nodeViewModel.start(
            arguments: buildArguments(),
            torSession: torEnabled ? torViewModel.sessionID : nil,
            torSocksPort: socksPort
        )
    }

    private func stopNode() {
        nodeViewModel.stop()
    }

    private var statusSymbol: String {
        switch nodeViewModel.nodeState {
        case .stopped: "power.circle"
        case .starting: "bolt.circle"
        case .running: "power.circle.fill"
        case .stopping: "bolt.circle"
        }
    }

    private var torStatusLabel: String {
        switch torViewModel.displayState {
        case .disabled: return "Tor Disabled"
        case .starting: return "Tor: \(torViewModel.bootstrapProgress)%"
        case .running:  return "Tor Connected"
        case .stopping: return "Tor Stopping"
        case .failed:   return "Tor Failed"
        }
    }

    private var torStatusSymbol: String {
        switch torViewModel.displayState {
        case .disabled: return "network.slash"
        case .starting: return "network.badge.shield.half.filled"
        case .running:  return "network"
        case .stopping: return "network.badge.shield.half.filled"
        case .failed:   return "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch nodeViewModel.nodeState {
        case .stopped: .secondary
        case .starting, .stopping: .orange
        case .running: .green
        }
    }
}

#Preview {
    ContentView()
}
