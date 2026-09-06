//
//  RunReporter.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// What an unattended run ended up doing.
///
/// Deliberately free of ActivityKit, UserNotifications and App Intents types so the
/// wording stays testable on the macOS leg of CI, where none of those compile in and
/// where a background-launched action cannot be exercised at all.
public enum RunOutcome: Sendable, Equatable {
    /// Refused to start because the private network was not ready (ADR 0006).
    case refusedPrivateNetworkUnavailable
    /// A node was already running, so it was read and left alone (ADR 0005).
    case adopted(height: Int)
    /// Ran until the deadline.
    ///
    /// `blocksGained` is a floor, never an exact count: the node keeps downloading
    /// while it shuts down and the height is read before that begins. Device runs
    /// showed up to 11 blocks arriving in that gap. `nil` means it could not be
    /// measured at all, which is a different statement from zero.
    case completed(height: Int, blocksGained: Int?, connections: Int?)
    /// The node never came up in the time available.
    case failed(reason: String)

    /// The single sentence a person sees. On an unattended run this is the only
    /// evidence the run happened — the dialog the action returns has nowhere to be
    /// displayed when nobody is watching.
    public var message: String {
        switch self {
        case .refusedPrivateNetworkUnavailable:
            return "The private network was not ready, so the node did not start."

        case let .adopted(height):
            return "A node was already running at height \(height) and was left alone."

        case let .completed(height, blocksGained, connections):
            var sentence = "Ran to height \(height)"
            if let blocksGained {
                sentence += ", gaining at least \(blocksGained) blocks"
            }
            sentence += "."
            // Gaining nothing with nobody to gain it from is a short-window problem;
            // gaining nothing despite peers is a different one. Only saying which
            // stops a working feature from looking broken.
            if blocksGained == 0, connections == 0 {
                sentence += " No connections were made in time."
            }
            return sentence

        case let .failed(reason):
            return "The node did not start: \(reason)."
        }
    }
}

/// Where a run reports to.
///
/// Neither method throws, and that is the point rather than an oversight: reporting
/// is a side effect of a run and must never be able to fail one. An implementation
/// that cannot deliver stays silent.
public protocol RunReporter: Sendable {
    /// Called before the private-network gate, so a refusal is still reported.
    ///
    /// Takes the deadline on the continuous clock — the same clock the run's own
    /// budget uses — rather than a wall-clock date. Converting is the reporter's
    /// problem, and only some reporters need to.
    func begin(startHeight: Int?, deadline: ContinuousClock.Instant) async
    func finish(_ outcome: RunOutcome) async
}

/// Reports nowhere. The default, and the whole implementation on macOS.
public struct NoOpReporter: RunReporter {
    public init() {}
    public func begin(startHeight: Int?, deadline: ContinuousClock.Instant) async {}
    public func finish(_ outcome: RunOutcome) async {}
}
