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
    /// Written as literal `AppShortcut(...)` calls — no brackets, no commas, no helper
    /// properties, no `.init(`. This shape is mandatory, not stylistic.
    ///
    /// A separate build step reads this list out of the *source text* to bake the app's
    /// actions into the bundle, so the Shortcuts app can list them without launching
    /// us. It works from compile-time constant values the compiler emits, and resolves
    /// nothing at runtime.
    ///
    /// What that build step does and does not accept, established by testing each
    /// shape against Xcode 26.4 and 27:
    ///
    /// - A computed helper property returning an `AppShortcut`, handed back with an
    ///   explicit `return`, **fails**: it opts out of the builder, so no constant
    ///   exists to read, and the build stops with "Expected an 'AppShortcut'
    ///   initialization call".
    /// - A bare `if #available(…) { AppShortcut(…) }` **is accepted** — the builder
    ///   handles that one construct specially.
    /// - `if #available(…) { … } else { … }` **fails** with "closure containing control
    ///   flow statement cannot be used with result builder". General branching is out.
    ///
    /// That last point is why there are two actions rather than one whose backing type
    /// changes with the system version: choosing between types needs an `else`. So the
    /// baseline is registered unconditionally, and the iOS 27 longer-running variant is
    /// added alongside it. On iOS 18–26 only the baseline exists; on iOS 27 a person
    /// sees both and picks the extended one to get the longer run. See plan §3.5.
    ///
    /// The compile fence is load-bearing, not defensive: without it Xcode 26.4 fails
    /// with "cannot find 'SyncNodeLongRunningIntent' in scope", because that type's own
    /// file is fenced out on toolchains without the iOS 27 SDK.
    static var appShortcuts: [AppShortcut] {
        // Several natural phrasings, as Apple recommends, so more than one way of
        // asking lands on the same action. English only for now; localization is a
        // follow-up (plan §7).
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
        #if compiler(>=6.4)
        // Distinct phrases and title: two actions that sounded alike would leave the
        // person — and Siri — no way to tell which one they were asking for.
        if #available(iOS 27.0, *) {
            AppShortcut(
                intent: SyncNodeLongRunningIntent(),
                phrases: [
                    "Sync my node with progress in \(.applicationName)",
                    "Sync my Bitcoin node with progress in \(.applicationName)",
                ],
                shortTitle: "Sync Bitcoin Node (Extended)",
                systemImageName: "bitcoinsign.circle"
            )
        }
        #endif
    }
}

#endif
