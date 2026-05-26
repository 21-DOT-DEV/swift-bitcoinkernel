//
//  SessionFactory.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

//  Shared test helper that hands out a pre-staged sequence of
//  ``TorSession`` fakes. Consumed by both `NodeAppTests` and
//  `KernelAppTests`.

import Foundation
import Tor

// MARK: - SessionFactory

/// Main-actor-safe factory that hands out a pre-staged sequence of fakes.
///
/// `TorViewModel` invokes the factory from `@MainActor`, so the internal
/// mutation is trivially safe — we just need a type that is `Sendable`
/// for the closure's `@Sendable` requirement.
@MainActor
final class SessionFactory {
    private var queue: [any TorSession]
    private(set) var callCount = 0

    init(_ sessions: [any TorSession]) {
        self.queue = sessions
    }

    nonisolated func make() -> @Sendable (TorConfiguration) -> any TorSession {
        { @Sendable [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return FakeTorSession() }
                self.callCount += 1
                return self.queue.isEmpty ? FakeTorSession() : self.queue.removeFirst()
            }
        }
    }
}
