//
//  BackgroundAssertion.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import os.log

// Phone and tablet only, for the reason recorded in
// Development/Specs/003-node-automation-action/plan.md §2. Excluded at compile
// time rather than by an availability annotation, which would still compile this
// into a Mac build and only refuse it at runtime.
#if os(iOS)

    // UIKit is the only iOS-only dependency here, so it is imported inside the
    // guard rather than at the top, where a Mac build would fail on it.
    import UIKit

/// Holds the system's "do not suspend this app" assertion for the length of a run.
///
/// The log showed the app raising none at all, which lets the system freeze it partway
/// through. For a Bitcoin node that means the data directory stays locked and the next
/// run cannot start. The expiry callback is a backstop only: it is given a couple of
/// seconds and a clean shutdown has been measured at up to 4.8, so shutting down must
/// already be underway by then rather than starting there.
@MainActor
final class BackgroundAssertion {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(name: String, onExpiry: @escaping @MainActor () -> Void) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // Documented to be called on the main thread. Asserting that rather than
            // hopping to it: a hop would land after the system has already killed us.
            MainActor.assumeIsolated {
                onExpiry()
                self?.end()
            }
        }
    }

    /// Deliberately safe to call twice, because both the normal path and the expiry
    /// callback end it and either can come first. Not ending it at all, or ending it
    /// twice, both get the app killed.
    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

#endif
