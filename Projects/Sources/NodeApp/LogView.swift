//
//  LogView.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import SwiftUI

/// Tails the daemon's `debug.log` with a coarse level filter and a share
/// action — the minimum an operator needs to debug a node on a device without
/// a terminal.
struct LogView: View {
    enum Level: String, CaseIterable, Identifiable {
        case all = "All", warnings = "Warnings", errors = "Errors"
        var id: String { rawValue }
    }

    @State private var level: Level = .all
    @State private var content = ""

    var body: some View {
        NavigationStack {
            Group {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        "No log output",
                        systemImage: "doc.text",
                        description: Text("Start the node to generate `debug.log`.")
                    )
                } else {
                    ScrollView {
                        Text(filtered)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            }
            .navigationTitle("debug.log")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Level", selection: $level) {
                        ForEach(Level.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: filtered) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(filtered.isEmpty)
                }
            }
            .task {
                while !Task.isCancelled {
                    content = DebugLog.tail()
                    try? await Task.sleep(for: .seconds(3))
                }
            }
        }
    }

    /// `debug.log` lines have no uniform level prefix, so the filter matches the
    /// word `error` / `warn` case-insensitively — coarse but useful for triage.
    private var filtered: String {
        let needle: String? = switch level {
        case .all: nil
        case .warnings: "warn"
        case .errors: "error"
        }
        guard let needle else { return content }
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { $0.lowercased().contains(needle) }
            .joined(separator: "\n")
    }
}
