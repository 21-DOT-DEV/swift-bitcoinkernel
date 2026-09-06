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
    /// The node was started.
    ///
    /// `blocksSinceLastCheck` counts from the last height this app recorded, not from
    /// the start of this run. The run itself gains almost nothing — it returns as soon
    /// as the node answers — while the node carries on downloading for minutes
    /// afterwards. Measuring from the last recorded height is what captures that.
    /// `nil` means no height was ever recorded, which is not the same as no progress.
    case completed(height: Int, blocksSinceLastCheck: Int?)
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

        case let .completed(height, blocksSinceLastCheck):
            let tip = "Node running at height \(height)."
            guard let blocksSinceLastCheck else { return tip }
            return blocksSinceLastCheck == 0
                ? tip + " No new blocks since the last check."
                : tip + " \(blocksSinceLastCheck) blocks since the last check."

        case let .failed(reason):
            return "The node did not start: \(reason)."
        }
    }
}
