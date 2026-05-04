//
//  RootViewTests.swift
//  21-DOT-DEV/Bitcoin
//
//  Smoke-level tests that `RootView` constructs against the
//  approved dependency shape (KernelAppViewModel + KernelAppSettings)
//  and that its `body` evaluates without hitting preconditions or
//  crashing. View tree inspection is deliberately kept light —
//  per-feature behavioural tests live with their feature's value
//  types (e.g. `SyncViewPresenterTests`).
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import BitcoinKernel
import Foundation
import SwiftUI
import Testing
@testable import KernelApp

@Suite("RootView")
@MainActor
struct RootViewTests {

    // MARK: - Helpers

    private func makeParts() -> (vm: KernelAppViewModel, settings: KernelAppSettings) {
        let suite = "dev.21.RootViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = KernelAppSettings(defaults: defaults)
        let vm = KernelAppViewModel(settings: settings)
        return (vm, settings)
    }

    // MARK: - Structural smoke

    @Test("RootView initializes with the required dependencies and evaluates body")
    func constructsAndEvaluatesBody() {
        let parts = makeParts()
        let root = RootView(viewModel: parts.vm, settings: parts.settings)
        // Force body evaluation; if any binding / environment wiring is
        // mis-shaped, this traps at runtime.
        _ = root.body
    }

    @Test("RootView exposes the two approved tabs")
    func tabInventoryIsSyncAndSettings() {
        // The tab list is a type-level constant so the test is a pure
        // assertion on the source of truth consumed by the view.
        let tabs = RootView.Tab.allCases
        #expect(tabs == [.sync, .settings])
    }

    @Test("RootView tab labels and symbols match the design spec")
    func tabLabelsAreCorrect() {
        #expect(RootView.Tab.sync.title == "Sync")
        #expect(RootView.Tab.sync.systemImage == "arrow.triangle.2.circlepath")
        #expect(RootView.Tab.settings.title == "Settings")
        #expect(RootView.Tab.settings.systemImage == "gearshape")
    }
}
