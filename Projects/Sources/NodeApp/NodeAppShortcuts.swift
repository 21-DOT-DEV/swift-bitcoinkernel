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
    // One user-visible action, backed by the longer-running type on iOS 27 and
    // the baseline type on iOS 18–26. The extended run only takes effect for the
    // type the system launches, so the right type must be the one registered —
    // hence the branch here rather than delegation. The iOS 27 branch is behind
    // the same compiler fence as the type itself, so the everyday Xcode 26 build
    // omits it. See plan §3.5.
    //
    // `AppShortcutsBuilder` accepts only a straight list of shortcuts — it has no
    // support for `if`/`else` — so the list is assembled by hand and handed back
    // with an explicit `return`, which also opts this body out of the builder.
    static var appShortcuts: [AppShortcut] {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            return [longRunningShortcut]
        }
        #endif
        return [baselineShortcut]
    }

    // Several natural phrasings, as Apple recommends, so more than one way of
    // asking lands on the same action. Every phrase must contain the app name
    // (`\(.applicationName)`), or it is accepted at build time but never matches
    // at run time. English only for now; localization is a follow-up (plan §7).
    // The phrase list is repeated per shortcut because a phrase is typed to its
    // specific intent and cannot be shared across two intent types.
    private static var baselineShortcut: AppShortcut {
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

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    private static var longRunningShortcut: AppShortcut {
        AppShortcut(
            intent: SyncNodeLongRunningIntent(),
            phrases: [
                "Sync my node in \(.applicationName)",
                "Sync my Bitcoin node in \(.applicationName)",
                "Run a node sync in \(.applicationName)",
            ],
            shortTitle: "Sync Bitcoin Node",
            systemImageName: "bitcoinsign.circle"
        )
    }
    #endif
}

#endif
