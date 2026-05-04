//
//  KernelApp.swift
//  21-DOT-DEV/Bitcoin
//
//  App entry point. Owns the root view model and settings at App
//  scope so the tab subtree re-subscribes to the same instance
//  across scene activations, and platform-specific window-frame
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
    @State private var viewModel: KernelAppViewModel

    init() {
        let settings = KernelAppSettings()
        _settings = State(wrappedValue: settings)
        _viewModel = State(wrappedValue: KernelAppViewModel(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: viewModel, settings: settings)
                #if os(macOS)
                .frame(minWidth: 620, minHeight: 400)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 720, height: 540)
        #endif
    }
}
