//
//  RootView.swift
//  21-DOT-DEV/Bitcoin
//
//  Root SwiftUI surface for KernelApp. A uniform TabView on iOS and
//  macOS with two peer tabs — Sync and Settings. Ownership of
//  KernelAppViewModel and KernelAppSettings lives one level up (in
//  `KernelApp`), wired in via initializer so the whole app can be
//  previewed with in-memory regtest fixtures.
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import SwiftUI

// MARK: - RootView

struct RootView: View {
    @Bindable var viewModel: KernelAppViewModel
    @Bindable var settings: KernelAppSettings
    @Bindable var tor: TorViewModel

    @State private var selection: Tab = .sync

    var body: some View {
        TabView(selection: $selection) {
            SwiftUI.Tab(Tab.sync.title, systemImage: Tab.sync.systemImage, value: Tab.sync) {
                SyncView(viewModel: viewModel, settings: settings, selectedTab: $selection)
            }

            SwiftUI.Tab(Tab.settings.title, systemImage: Tab.settings.systemImage, value: Tab.settings) {
                SettingsView(viewModel: viewModel, settings: settings, tor: tor)
            }
        }
    }
}

// MARK: - Tab inventory

extension RootView {
    /// Source of truth for the tab surface — peer to ``TabView`` selection
    /// state and consumed by tests to pin the approved inventory.
    enum Tab: String, Hashable, CaseIterable {
        case sync
        case settings

        var title: String {
            switch self {
            case .sync: "Sync"
            case .settings: "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .sync: "arrow.triangle.2.circlepath"
            case .settings: "gearshape"
            }
        }
    }
}
