//
//  CommandDetailView.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import SwiftUI

struct CommandDetailView: View {
    let command: RPCCommand
    @Bindable var viewModel: CommandsViewModel
    var nodeViewModel: NodeViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Command info
                VStack(alignment: .leading, spacing: 8) {
                    Label(command.category.rawValue, systemImage: command.category.systemImage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(command.name)
                        .font(.title2.monospaced().bold())

                    Text(command.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                // Execute button
                Button {
                    Task {
                        await viewModel.execute(command)
                    }
                } label: {
                    HStack {
                        if viewModel.isExecuting(command) {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(viewModel.isExecuting(command) ? "Executing…" : "Execute")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!nodeViewModel.isRunning || viewModel.isExecuting(command))

                if nodeViewModel.isSyncing && command.isHeavyDuringIBD {
                    Label(
                        "May be slow during initial sync — can temporarily pause block processing",
                        systemImage: "tortoise"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                }

                if !nodeViewModel.isRunning {
                    Label("Start the node to execute commands", systemImage: "power.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                // Error message
                if let errorMessage = viewModel.error(for: command) {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                // Response area
                if let json = viewModel.response(for: command) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Response")
                                .font(.headline)
                            Spacer()
                            Button {
                                #if canImport(UIKit)
                                UIPasteboard.general.string = json
                                #elseif canImport(AppKit)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(json, forType: .string)
                                #endif
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.caption)
                            }
                        }

                        ScrollView(.horizontal) {
                            Text(json)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .padding()
                        }
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding()
        }
        .navigationTitle(command.methodName)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
