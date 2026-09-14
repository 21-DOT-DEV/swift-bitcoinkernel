//
//  NodeApp.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2022-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import SwiftUI

@main
struct NodeApp: App {
    init() {
        // Started here, at process launch, rather than when a window appears: the
        // Shortcuts actions run with no window at all, so anything started alongside
        // the interface would never start for them. Watching from launch means the
        // network answer is ready — within milliseconds — by the time a run reads it.
        #if os(iOS)
            NetworkCostMonitor.shared.start()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
