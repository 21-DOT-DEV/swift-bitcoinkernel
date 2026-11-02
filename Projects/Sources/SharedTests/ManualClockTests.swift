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
        clock.advance(by: .seconds(1))
        // The start instant is now in the past — already due.
        try await clock.sleep(until: ManualClock.Instant(offset: .zero))
    }

    @Test("a sleep registered behind now returns instead of parking")
    func lateRegistrationReturns() async throws {
        let clock = ManualClock()
        clock.advance(by: .seconds(10))
        // Registered five seconds behind the advanced instant — due at once.
        try await clock.sleep(until: ManualClock.Instant(offset: .seconds(5)))
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

    @Test("a deadline wait returns the earliest parked deadline at once", .timeLimit(.minutes(1)))
    func waitReturnsEarliestParked() async throws {
        let clock = ManualClock()
        let near = Task {
            try await clock.sleep(until: clock.now.advanced(by: .seconds(5)))
        }
        let far = Task {
            try await clock.sleep(until: clock.now.advanced(by: .seconds(60)))
        }
        var spins = 0
        while clock.parkedSleepers < 2, spins < 10_000 {
            await Task.yield()
            spins += 1
        }
        try #require(clock.parkedSleepers == 2)
        let deadline = try await clock.waitForNextDeadline()
        #expect(deadline == clock.now.advanced(by: .seconds(5)))
        near.cancel()
        far.cancel()
        _ = try? await near.value
        _ = try? await far.value
    }

    @Test("a deadline wait suspends until a sleeper parks, then delivers it", .timeLimit(.minutes(1)))
    func waitSuspendsUntilParked() async throws {
        let clock = ManualClock()
        let waiter = Task { try await clock.waitForNextDeadline() }
        var spins = 0
        while clock.armedWaiterCount == 0, spins < 10_000 {
            await Task.yield()
            spins += 1
        }
        try #require(clock.armedWaiterCount == 1)
        let sleeper = Task {
            try await clock.sleep(until: clock.now.advanced(by: .seconds(30)))
        }
        let deadline = try await waiter.value
        #expect(deadline == clock.now.advanced(by: .seconds(30)))
        #expect(clock.armedWaiterCount == 0)
        sleeper.cancel()
        _ = try? await sleeper.value
    }

    @Test("a deadline wait cancelled while parked throws CancellationError", .timeLimit(.minutes(1)))
    func cancelWaiter() async throws {
        let clock = ManualClock()
        let waiter = Task { try await clock.waitForNextDeadline() }
        var spins = 0
        while clock.armedWaiterCount == 0, spins < 10_000 {
            await Task.yield()
            spins += 1
        }
        try #require(clock.armedWaiterCount == 1)
        waiter.cancel()
        await #expect(throws: CancellationError.self) {
            try await waiter.value
        }
        #expect(clock.armedWaiterCount == 0)
    }

    @Test("a drive returns when its done gate opens with nothing parked", .timeLimit(.minutes(1)))
    func driveReturnsOnDone() async throws {
        let clock = ManualClock()
        let done = Gate()
        let driver = Task {
            try await clock.drive(untilDone: done, by: .milliseconds(600))
        }
        // Nothing ever parks — the drive is suspended on the arm-wait, so
        // opening the gate is the only exit, and it must arrive.
        done.open()
        try await driver.value
    }

    @Test("a drive cancelled while suspended throws CancellationError", .timeLimit(.minutes(1)))
    func driveCancelled() async throws {
        let clock = ManualClock()
        let driver = Task {
            try await clock.drive(untilDone: Gate(), by: .milliseconds(600))
        }
        driver.cancel()
        await #expect(throws: CancellationError.self) {
            try await driver.value
        }
    }
}
