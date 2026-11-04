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

/// An `ObservedClock` over a fresh `ManualClock`, plus the gate its
/// reporter opens the first time a watch-budgeted question arms its
/// bound — anything past twenty seconds cannot be the short action's
/// 10 s bound, a nap, or a conditions gather. File scope because the
/// suite's tests all need the same triple.
func watchClock() -> (
    test: ManualClock, questionArmed: Gate,
    log: SleepLog, clock: ObservedClock
) {
    let test = ManualClock()
    let questionArmed = Gate()
    let log = SleepLog()
    let clock = ObservedClock(base: test) { deadline, _ in
        let requested = test.now.duration(to: deadline)
        log.durations.withLock { $0.append(requested) }
        if requested > .seconds(20) { questionArmed.open() }
    }
    return (test, questionArmed, log, clock)
}

#endif
