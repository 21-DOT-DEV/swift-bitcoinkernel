//
//  NodeAppShortcuts.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import AppIntents

// Phone and tablet only, for the reason recorded in
// Development/Specs/003-node-automation-action/plan.md §2. Excluded at compile
// time rather than by an availability annotation, which would still compile this
// into a Mac build and only refuse it at runtime.
#if os(iOS)

struct NodeAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SyncNodeIntent(),
            phrases: ["Sync my node in \(.applicationName)"],
            shortTitle: "Sync Bitcoin Node",
            systemImageName: "bitcoinsign.circle"
        )
    }
}

#endif
