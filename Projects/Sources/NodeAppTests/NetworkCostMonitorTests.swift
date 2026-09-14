//
//  NetworkCostMonitorTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import Synchronization
import Testing
@testable import NodeApp

@Suite("Network cost watcher")
struct NetworkCostMonitorTests {

    @Test("an unreported network fails open, not closed")
    func unknownIsNotCostly() {
        // Refusing whenever the network is unreported would ground every run on a
        // device that has not reported yet — the same call NodePreflight makes for
        // unknown free space.
        let monitor = NetworkCostMonitor { _ in NSObject() }
        #expect(monitor.current == .unknown)
        #expect(monitor.current.isMetered == false)
        #expect(monitor.current.isDataRestricted == false)
    }

    @Test("the latest report is the one a run reads")
    func latestReportWins() {
        let sink = Mutex<(@Sendable (NetworkCost) -> Void)?>(nil)
        let monitor = NetworkCostMonitor { report in
            sink.withLock { $0 = report }
            return NSObject()
        }
        monitor.start()

        sink.withLock { $0?(NetworkCost(isMetered: true, isDataRestricted: false)) }
        #expect(monitor.current == NetworkCost(isMetered: true, isDataRestricted: false))

        sink.withLock { $0?(NetworkCost(isMetered: false, isDataRestricted: true)) }
        #expect(monitor.current == NetworkCost(isMetered: false, isDataRestricted: true))
    }

    @Test("a second start does not ask the source again")
    func startIsOnce() {
        // Stopping and restarting the underlying watcher is what produces bursts of
        // repeated reports, so only the first call may have effect.
        let invocations = Mutex(0)
        let monitor = NetworkCostMonitor { _ in
            invocations.withLock { $0 += 1 }
            return NSObject()
        }
        monitor.start()
        monitor.start()
        #expect(invocations.withLock { $0 } == 1)
    }
}
