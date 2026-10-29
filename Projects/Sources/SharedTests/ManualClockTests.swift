//
//  ManualClockTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing

// `ManualClock` lives in SharedTests — Foundation-only, so no discriminator.
// These cases pin the single-resume invariants the migrated suites rely on:
// a regression here surfaces as a `CheckedContinuation` double-resume crash
// or a permanently parked sleeper inside an unrelated suite.
struct ManualClockTests {

    @Test("a sleep at or past now returns without an advance")
    func sleepAtNowReturns() async throws {
        let clock = ManualClock()
        try await clock.sleep(until: clock.now)
        try await clock.sleep(until: clock.now.advanced(by: -.seconds(1)))
    }

    @Test("a sleep registered behind now returns instead of parking")
    func lateRegistrationReturns() async throws {
        let clock = ManualClock()
        clock.advance(by: .seconds(10))
        // Registered five seconds behind the advanced instant — due at once.
        try await clock.sleep(until: clock.now.advanced(by: -.seconds(5)))
    }

    @Test("a parked sleeper cancelled mid-wait throws CancellationError")
    func cancelWhileParked() async throws {
        let clock = ManualClock()
        let task = Task {
            try await clock.sleep(until: clock.now.advanced(by: .seconds(60)))
        }
        var spins = 0
        while clock.parkedSleepers == 0, spins < 10_000 {
            await Task.yield()
            spins += 1
        }
        try #require(clock.parkedSleepers == 1)
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(clock.parkedSleepers == 0)
    }

    @Test("a sleep called on an already-cancelled task throws")
    func cancelBeforeRegistration() async throws {
        let clock = ManualClock()
        let proceed = Gate()
        let task = Task {
            await proceed.waitIgnoringCancellation()
            try await clock.sleep(until: clock.now.advanced(by: .seconds(60)))
        }
        task.cancel()
        proceed.open()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(clock.parkedSleepers == 0)
    }
}
