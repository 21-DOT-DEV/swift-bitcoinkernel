//
//  CommandsView.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2022-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import SwiftUI

struct CommandsView: View {
    @Bindable var viewModel: CommandsViewModel
    var nodeViewModel: NodeViewModel
    var torViewModel: TorViewModel
    var buildArguments: () -> [String] = { [] }

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.commandsByCategory, id: \.category) { section in
                    Section {
                        ForEach(section.commands) { command in
                            NavigationLink(value: command) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(command.name)
                                        .font(.body.monospaced())
                                    Text(command.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    } header: {
                        Label(section.category.rawValue, systemImage: section.category.systemImage)
                    }
                }
            }
            .navigationTitle("Commands")
            .searchable(text: $viewModel.searchText, prompt: "Search commands")
            .navigationDestination(for: RPCCommand.self) { command in
                CommandDetailView(command: command, viewModel: viewModel, nodeViewModel: nodeViewModel)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NodeToolbarMenu(nodeViewModel: nodeViewModel, torViewModel: torViewModel, buildArguments: buildArguments)
                }
            }
        }
    }
}
