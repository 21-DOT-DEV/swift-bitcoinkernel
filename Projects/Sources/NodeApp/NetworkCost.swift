//
//  NetworkCost.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import Network
import Synchronization
import os.log

/// Whether the current network is one a person would mind a multi-gigabyte download on.
///
/// Two separate facts, because either alone should stop a chain sync:
///   * **metered** — cellular, or a link shared from another phone. Costs money.
///   * **data-restricted** — the person switched on Low Data Mode for this network,
///     asking the system to use as little data as possible. Low Data Mode on home
///     wireless is restricted but *not* metered, which is why one flag cannot cover both.
struct NetworkCost: Equatable, Sendable {
    var isMetered: Bool
    var isDataRestricted: Bool

    /// Treated as "not costly" when the network is not yet known.
    ///
    /// Deliberately failing open, matching how unknown free space is handled in
    /// `NodePreflight`: refusing whenever unsure would ground every run on a
    /// device that has not reported yet, which is worse than occasionally
    /// starting on a network we could not classify.
    static let unknown = NetworkCost(isMetered: false, isDataRestricted: false)
}

/// Watches the network for as long as the app is alive, so a run can read the answer
/// instead of waiting for one.
///
/// **Why a standing watcher rather than asking on demand.** The system announces
/// network changes; it does not answer questions. Bridging that into a single answer
/// means suspending until a report arrives — and an earlier version of this file did
/// exactly that and could hang forever, because nothing resumed the bridge if no report
/// came, which would stall a run before it ever reached the node. Reading a value that
/// is already there removes that failure entirely. Two further reasons this shape is
/// right: the "current" value can be read directly but is documented as sometimes
/// stale, and starting a watcher delivers one report immediately, so a standing watcher
/// is populated within milliseconds of app launch at no extra cost.
///
/// The watcher is started once and never stopped and restarted, because stopping and
/// restarting is what produces bursts of repeated reports.
///
/// State is held in a `Mutex` from the Synchronization framework — the house pattern
/// here, matching `Sources/BitcoinKernel/Sync/Internal/SyncStorage.swift` — because
/// reports arrive on a background queue while a run reads from the interface thread.
final class NetworkCostMonitor: Sendable {
    static let shared = NetworkCostMonitor()

    /// A source of cost reports: invoked once by ``start()``, and thereafter
    /// reports the network's cost whenever that cost changes.
    ///
    /// The returned token is retained for the life of the monitor — for the real
    /// source it is the `NWPathMonitor` itself, which stops reporting the moment
    /// nothing holds it. The seam exists because `NWPath` has no public
    /// initializer: no test can make Apple's monitor report a metered path, so a
    /// test substitutes a source that emits any `NetworkCost` on demand.
    typealias Source = @Sendable (
        _ report: @escaping @Sendable (NetworkCost) -> Void
    ) -> AnyObject

    private let log = Logger(subsystem: "dev.21.NodeApp", category: "NetworkCost")
    private let source: Source

    /// The latest report, or `nil` until the first one arrives.
    private let latest = Mutex<NetworkCost?>(nil)
    private let started = Mutex<Bool>(false)

    /// Keeps the source's token — the `NWPathMonitor` — alive.
    private let sourceToken = Mutex<AnyObject?>(nil)

    private init() {
        self.source = NetworkCostMonitor.pathMonitor
    }

    /// Test seam: a monitor whose reports come from the given source rather
    /// than the system. Internal rather than private so the test bundle can
    /// reach it; the shared monitor still uses the real source.
    init(source: @escaping Source) {
        self.source = source
    }

    /// Begins watching. Safe to call more than once; only the first call has effect.
    ///
    /// Called at app launch so the answer is ready before any run needs it —
    /// including a run on a background launch, where the app starts and the action
    /// follows within milliseconds.
    func start() {
        let alreadyStarted = started.withLock { wasStarted -> Bool in
            if wasStarted { return true }
            wasStarted = true
            return false
        }
        guard !alreadyStarted else { return }

        // Captures this object rather than its stored lock: the lock cannot be
        // copied into a closure. Held strongly on purpose — this watcher lives as
        // long as the process.
        let token = source { [self] cost in
            record(cost)
        }
        sourceToken.withLock { $0 = token }
    }

    /// The latest known answer, or `.unknown` if no report has arrived yet.
    ///
    /// Never waits. A run that reads this before the first report proceeds as
    /// though the network is not costly — the deliberate fail-open choice above.
    var current: NetworkCost {
        latest.withLock { $0 } ?? .unknown
    }

    /// Suspends until the first report arrives and returns it.
    ///
    /// `current` never waits, which suits a long-lived process where "not yet
    /// reported" is a brief startup blip. A run launched straight into the
    /// background reaches its read within milliseconds of `start()`, when "not
    /// yet reported" is the normal state rather than the blip — and reading it
    /// as "not costly" would skip the one refusal that protects the person's
    /// data allowance. This is the read for that path; how long it may wait is
    /// the caller's call, bounded there rather than here.
    ///
    /// The wait is a poll, not a suspended continuation: the answer it looks
    /// for can only turn from "nothing yet" into "the first report" — a
    /// one-way change a periodic check observes just as surely, and there is
    /// no parked wait for cancellation to have to find and release. A
    /// cancelled task simply stops waiting and gets the answer `current`
    /// gives — `.unknown` until a report exists. Fifty milliseconds is far
    /// finer than the seconds-scale bound callers put on this read.
    func first() async -> NetworkCost {
        while !Task.isCancelled {
            if let cost = latest.withLock({ $0 }) { return cost }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return current
    }

    /// The production source: Apple's `NWPathMonitor`, which announces network
    /// changes rather than answering questions. Starting it delivers one report
    /// immediately.
    private static func pathMonitor(
        report: @escaping @Sendable (NetworkCost) -> Void
    ) -> AnyObject {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            report(NetworkCost(
                isMetered: path.isExpensive, isDataRestricted: path.isConstrained))
        }
        monitor.start(queue: queue)
        return monitor
    }

    /// Process-lifetime queue for path reports. Static so it cannot be released
    /// while the monitor it serves is still running.
    private static let queue = DispatchQueue(label: "dev.21.NodeApp.networkCost")

    /// Stores a report, logging only when the answer actually changed — repeated
    /// identical reports are ordinary (moving between foreground and background
    /// produces them) and only a real change is worth a log line.
    private func record(_ cost: NetworkCost) {
        let changed = latest.withLock { current -> Bool in
            guard current != cost else { return false }
            current = cost
            return true
        }
        if changed {
            log.notice(
                "network: metered = \(cost.isMetered, privacy: .public), data-restricted = \(cost.isDataRestricted, privacy: .public)"
            )
        }
    }
}
