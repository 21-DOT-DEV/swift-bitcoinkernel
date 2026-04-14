//
//  ContentView.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import SwiftUI

enum AppTab: String, Hashable {
    case commands = "Commands"
    case configuration = "Configuration"
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .commands
    @State private var nodeViewModel = NodeViewModel()
    @State private var commandsViewModel = CommandsViewModel()

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Commands", systemImage: "terminal", value: .commands) {
                CommandsView(
                    viewModel: commandsViewModel,
                    nodeViewModel: nodeViewModel,
                    buildArguments: ConfigurationView.buildArguments
                )
            }

            Tab("Configuration", systemImage: "gearshape.2", value: .configuration) {
                ConfigurationView(nodeViewModel: nodeViewModel)
            }
        }
    }
}

// MARK: - Node Toolbar Menu

struct NodeToolbarMenu: View {
    @Bindable var nodeViewModel: NodeViewModel
    var buildArguments: () -> [String] = { [] }

    var body: some View {
        Menu {
            Section {
                Label(nodeViewModel.nodeState.rawValue, systemImage: statusSymbol)
            }

            if nodeViewModel.nodeState == .stopped {
                Button {
                    nodeViewModel.start(arguments: buildArguments())
                } label: {
                    Label("Start Node", systemImage: "play.fill")
                }
            }

            if nodeViewModel.nodeState == .running {
                Button(role: .destructive) {
                    nodeViewModel.stop()
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

    private var statusSymbol: String {
        switch nodeViewModel.nodeState {
        case .stopped: "power.circle"
        case .starting: "bolt.circle"
        case .running: "power.circle.fill"
        case .stopping: "bolt.circle"
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
