//
//  NotificationReporter.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import UserNotifications

/// Reports an unattended run as a local notification.
///
/// Chosen over a Live Activity for a once-daily overnight automation, for two reasons
/// that only apply at that cadence. A Live Activity's receipt is removed four hours
/// after it ends, so a 3am run is gone before anyone wakes; a notification waits in
/// Notification Center until it is read. And the card's advantage — updating in place
/// rather than stacking up — needs a stack to be worth having, which one run a day
/// does not produce. See Development/Specs/003-node-automation-action/plan.md §7.
public struct NotificationReporter: RunReporter {

    /// A fixed identifier, so each run replaces the previous run's notification
    /// rather than adding to a pile. This is the update-in-place behaviour the Live
    /// Activity was wanted for, without a widget extension to deliver it.
    private static let identifier = "dev.21.NodeApp.unattended-run"

    public init() {}

    public func begin(startHeight: Int?, deadline: ContinuousClock.Instant) async {}

    public func finish(_ outcome: RunOutcome) async {
        let center = UNUserNotificationCenter.current()
        guard await Self.canPost(center) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Bitcoin node"
        content.body = outcome.message
        // No sound: the whole point is a run nobody was asked to attend.
        content.sound = nil
        content.interruptionLevel = .passive

        let request = UNNotificationRequest(
            identifier: Self.identifier, content: content, trigger: nil
        )
        // Delivery failure must not fail the run (see `RunReporter`).
        try? await center.add(request)
    }

    /// Whether a notification can be posted without ever interrupting anyone.
    ///
    /// Asks for provisional authorisation, which is granted without showing a
    /// permission prompt and delivers quietly to Notification Center. That matters
    /// here: an unattended run has no interface, so a prompt raised from it could not
    /// be answered, and a run must never be the thing that asks.
    private static func canPost(_ center: UNUserNotificationCenter) async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .provisional])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
}
