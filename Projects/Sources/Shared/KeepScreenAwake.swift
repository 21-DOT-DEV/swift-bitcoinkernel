//
//  KeepScreenAwake.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import SwiftUI

/// Keeps the device screen awake while an app is on-screen.
///
/// On iPhone/iPad this disables the auto-lock idle timer; on Mac it holds a
/// display-sleep power assertion while the app is the front window. The
/// controller is idempotent: it holds exactly one platform assertion and only
/// begins/ends on a state transition, so repeated `update(enabled:isActive:)`
/// calls never leak.
///
/// The platform effect is injected as `onBegin`/`onEnd` so unit tests can
/// verify the begin-once/end-once behavior without touching real system APIs.
@MainActor
final class ScreenWakeController {
    private var held = false
    private let onBegin: (() -> Void)?
    private let onEnd: (() -> Void)?

    #if os(macOS)
    private var token: (any NSObjectProtocol)?
    #endif

    init(onBegin: (() -> Void)? = nil, onEnd: (() -> Void)? = nil) {
        self.onBegin = onBegin
        self.onEnd = onEnd
    }

    /// Applies the desired keep-awake state. Awake only when `enabled` and the
    /// app is on-screen/active. A no-op when the resulting state is unchanged.
    func update(enabled: Bool, isActive: Bool) {
        let shouldKeepAwake = enabled && isActive
        if shouldKeepAwake, !held {
            held = true
            beginEffect()
        } else if !shouldKeepAwake, held {
            held = false
            endEffect()
        }
    }

    private func beginEffect() {
        if let onBegin { onBegin(); return }
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = true
        #elseif os(macOS)
        token = ProcessInfo.processInfo.beginActivity(
            options: .idleDisplaySleepDisabled, reason: "Keep Screen Awake")
        #endif
    }

    private func endEffect() {
        if let onEnd { onEnd(); return }
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = false
        #elseif os(macOS)
        if let token {
            ProcessInfo.processInfo.endActivity(token)
            self.token = nil
        }
        #endif
    }
}

/// Applies keep-awake to a view hierarchy while `enabled` and the app is the
/// active/front window. iPhone/iPad read `scenePhase`; Mac reads `appearsActive`
/// (`scenePhase` does not report focus loss on Mac).
private struct KeepScreenAwakeModifier: ViewModifier {
    let enabled: Bool
    @State private var controller = ScreenWakeController()

    #if os(macOS)
    @Environment(\.appearsActive) private var appearsActive
    #else
    @Environment(\.scenePhase) private var scenePhase
    #endif

    func body(content: Content) -> some View {
        content
            .onAppear { apply() }
            .onChange(of: enabled) { apply() }
            #if os(macOS)
            .onChange(of: appearsActive) { apply() }
            #else
            .onChange(of: scenePhase) { apply() }
            #endif
            .onDisappear { controller.update(enabled: false, isActive: false) }
    }

    private func apply() {
        #if os(macOS)
        let isActive = appearsActive
        #else
        let isActive = scenePhase == .active
        #endif
        controller.update(enabled: enabled, isActive: isActive)
    }
}

extension View {
    /// Keeps the screen awake while `enabled` and this app is the front window.
    func keepScreenAwake(_ enabled: Bool) -> some View {
        modifier(KeepScreenAwakeModifier(enabled: enabled))
    }
}
