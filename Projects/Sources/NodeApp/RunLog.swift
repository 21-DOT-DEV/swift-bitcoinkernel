//
//  RunLog.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import os.log

// Phone and tablet only, for the reason recorded in
// Development/Specs/003-node-automation-action/plan.md §2. Excluded at compile
// time rather than by an availability annotation, which would still compile this
// into a Mac build and only refuse it at runtime.
#if os(iOS)

enum RunLog {
    static let logger = Logger(subsystem: "dev.21.NodeApp", category: "Shortcut")

    static func entered(privacyEnabled: Bool) {
        logger.notice(
            "run: entered, privacy network enabled = \(privacyEnabled, privacy: .public)")
    }

    static func decided(_ step: String) {
        logger.notice("run: step = \(step, privacy: .public)")
    }

    static func mark(_ event: String, msSinceStart: Int) {
        logger.notice("run: \(event, privacy: .public) at \(msSinceStart, privacy: .public) ms")
    }

    static func interrupted(msSinceStart: Int) {
        // The reason the run ended, which the failure notice never says.
        logger.notice("run: INTERRUPTED by the system at \(msSinceStart, privacy: .public) ms")
    }

    static func finished(outcome: String, height: Int, msSinceStart: Int) {
        logger.notice(
            "run: finished \(outcome, privacy: .public), height \(height, privacy: .public), total \(msSinceStart, privacy: .public) ms"
        )
    }

    static func failed(_ reason: String, msSinceStart: Int) {
        logger.error(
            "run: FAILED \(reason, privacy: .public) at \(msSinceStart, privacy: .public) ms")
    }
}

/// What an unattended run did.

#endif
