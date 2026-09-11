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
    /// Deliberately failing open, matching how unknown free space is handled: refusing
    /// whenever unsure would ground every run on a device that has not reported yet,
    /// which is worse than occasionally starting on a network we could not classify.
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

    private let log = Logger(subsystem: "dev.21.NodeApp", category: "NetworkCost")
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "dev.21.NodeApp.networkCost")

    /// The latest report, or `nil` until the first one arrives.
    private let latest = Mutex<NetworkCost?>(nil)
    private let started = Mutex<Bool>(false)

    private init() {}

    /// Begins watching. Safe to call more than once; only the first call has effect.
    ///
    /// Called at app launch so the answer is ready before any run needs it — including
    /// a run on a background launch, where the app starts and the action follows within
    /// milliseconds.
    func start() {
        let alreadyStarted = started.withLock { wasStarted -> Bool in
            if wasStarted { return true }
            wasStarted = true
            return false
        }
        guard !alreadyStarted else { return }

        // Captures this object rather than its stored lock: the lock cannot be copied
        // into a closure. Held strongly on purpose — this is a single shared watcher
        // that lives as long as the process.
        monitor.pathUpdateHandler = { path in
            let cost = NetworkCost(
                isMetered: path.isExpensive, isDataRestricted: path.isConstrained)
            // Repeated identical reports are ordinary — moving between foreground and
            // background produces them with nothing actually changed — so only a real
            // change is worth a log line.
            let changed = self.latest.withLock { current -> Bool in
                guard current != cost else { return false }
                current = cost
                return true
            }
            if changed {
                self.log.notice(
                    "network: metered = \(cost.isMetered, privacy: .public), data-restricted = \(cost.isDataRestricted, privacy: .public)"
                )
            }
        }
        monitor.start(queue: queue)
    }

    /// The latest known answer, or `.unknown` if no report has arrived yet.
    ///
    /// Never waits. A run that reads this before the first report proceeds as though the
    /// network is not costly, which is the deliberate fail-open choice above.
    var current: NetworkCost {
        latest.withLock { $0 } ?? .unknown
    }
}
