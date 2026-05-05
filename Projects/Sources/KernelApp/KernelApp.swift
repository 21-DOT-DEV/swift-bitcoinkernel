//
//  KernelApp.swift
//  21-DOT-DEV/Bitcoin
//
//  App entry point. Owns the root view model, settings, and Tor view
//  model at App scope so the tab subtree re-subscribes to the same
//  instances across scene activations. Platform-specific window-frame
//  preferences live here.
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import SwiftUI

@main
struct KernelApp: App {
    @State private var settings = KernelAppSettings()
    @State private var tor = TorViewModel(subsystem: "dev.21.KernelApp")
    @State private var viewModel: KernelAppViewModel

    init() {
        let settings = KernelAppSettings()
        let tor = TorViewModel(subsystem: "dev.21.KernelApp")
        _settings = State(wrappedValue: settings)
        _tor = State(wrappedValue: tor)
        _viewModel = State(wrappedValue: KernelAppViewModel(settings: settings, tor: tor))
    }

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: viewModel, settings: settings, tor: tor)
                #if os(macOS)
                .frame(minWidth: 620, minHeight: 400)
                #endif
                .task {
                    // Auto-start Tor at launch if the user has opted
                    // into Tor-routed downloads. Idempotent — second
                    // activation is a no-op.
                    if settings.routeDownloadsThroughTor {
                        tor.start()
                    }
                }
        }
        #if os(macOS)
        .defaultSize(width: 720, height: 540)
        #endif
    }
}
