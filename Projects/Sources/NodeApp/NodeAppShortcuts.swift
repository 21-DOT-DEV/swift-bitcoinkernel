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
// Development/Specs/003-node-automation-action/plan.md §2 and in SyncNodeIntent.
#if os(iOS)

/// Publishes the action so it appears in the Shortcuts app and can be added to an
/// automation there (the Automations tab), which runs it unattended on a schedule
/// or trigger.
///
/// The spoken phrase must contain the app name (`\(.applicationName)`): Siri uses
/// it to tell one app's actions apart from another's, and a phrase without it is
/// accepted at build time but never matches at runtime.
struct NodeAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Several natural phrasings, as Apple recommends, so more than one way of
        // asking lands on the same action. Every phrase must contain the app name
        // (`\(.applicationName)`), or it is accepted at build time but never matches
        // at run time. English only for now; localization is a follow-up (plan §7).
        AppShortcut(
            intent: SyncNodeIntent(),
            phrases: [
                "Sync my node in \(.applicationName)",
                "Sync my Bitcoin node in \(.applicationName)",
                "Run a node sync in \(.applicationName)",
            ],
            shortTitle: "Sync Bitcoin Node",
            systemImageName: "bitcoinsign.circle"
        )
    }
}

#endif
