//
//  WatchClock.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Synchronization

// `NodeRun` and `NodeRunReport` exist only in phone and tablet builds — the
// same compile-time gate as the sources, so these helpers are empty on a
// Mac build.
#if os(iOS)

/// The sleep-request log the watch tests share — a reference wrapper so
/// it can ride a tuple: `Mutex` is noncopyable.
final class SleepLog: Sendable {
    let durations = Mutex<[Duration]>([])
}

/// An `ObservedClock` over a fresh `ManualClock`, plus the log its
/// reporter appends every armed request to. File scope because the
/// suite's tests all need the same triple.
func watchClock() -> (test: ManualClock, log: SleepLog, clock: ObservedClock) {
    let test = ManualClock()
    let log = SleepLog()
    let clock = ObservedClock(base: test) { deadline, _ in
        log.durations.withLock { $0.append(test.now.duration(to: deadline)) }
    }
    return (test, log, clock)
}

#endif
