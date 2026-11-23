//
//  GateTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing

// `Gate` lives in SharedTests and is Foundation-only, so no discriminator.
// These cases pin the second ending: a gate that was abandoned releases
// its waiters with a named error and never reads as open, so a test
// waiting on a checkpoint the run never reached fails at once instead of
// carrying on or wedging to `.timeLimit`.
struct GateTests {

    @Test("a wait on an abandoned gate throws, naming the line it was written on", .timeLimit(.minutes(1)))
    func waitAfterAbandonThrows() async throws {
        let gate = Gate()
        gate.abandon()
        // Inside the macro, `#line` reads as the `#expect` line itself.
        let expected = #line + 1
        let error = await #expect(throws: Gate.Abandoned.self) {
            try await gate.wait()
        }
        #expect(error?.line == expected)
        #expect(error?.fileID.hasSuffix("GateTests.swift") == true)
        #expect(!gate.isOpen)
    }

    /// The two calls contend on purpose: the waiter may be registering while
    /// the abandon takes the lock. Both orders must end the same way, and a
    /// double release would stop the test process. Each order on its own is
    /// pinned by `waitAfterAbandonThrows` and `abandonReleasesParkedWaiter`.
    @Test("abandoning releases a waiter with the error, whichever lands first", .timeLimit(.minutes(1)))
    func abandonReleasesWaiter() async throws {
        let gate = Gate()
        let waiter = Task { try await gate.wait() }
        gate.abandon()
        await #expect(throws: Gate.Abandoned.self) {
            try await waiter.value
        }
    }

    /// The parked path itself, on its own: the race above almost always
    /// lands abandon-first, so it cannot pin what a checkpoint await
    /// actually does when the run ends early — the wait is suspended
    /// *before* the abandon arrives. The gate's registration report makes
    /// that order a fact instead of a bet.
    @Test("abandoning releases a parked wait with the error", .timeLimit(.minutes(1)))
    func abandonReleasesParkedWaiter() async throws {
        let armed = Gate()
        let gate = Gate(onWaiterArmed: { armed.open() })
        let expected = #line + 1
        let waiter = Task { try await gate.wait() }
        try await armed.wait()
        gate.abandon()
        let error = await #expect(throws: Gate.Abandoned.self) {
            try await waiter.value
        }
        #expect(error?.line == expected)
        #expect(error?.fileID.hasSuffix("GateTests.swift") == true)
    }

    @Test("an opened gate stays open through a later abandon", .timeLimit(.minutes(1)))
    func openThenAbandonStaysOpen() async throws {
        let gate = Gate()
        gate.open()
        gate.abandon()
        try await gate.wait()
        #expect(gate.isOpen)
    }

    @Test("an abandoned gate stays abandoned through a later open", .timeLimit(.minutes(1)))
    func abandonThenOpenStaysAbandoned() async throws {
        let gate = Gate()
        gate.abandon()
        gate.open()
        await #expect(throws: Gate.Abandoned.self) {
            try await gate.wait()
        }
        #expect(!gate.isOpen)
    }

    /// The two calls contend on purpose: the waiter may be registering while
    /// the abandon takes the lock. Both orders must end the same way, and a
    /// double release would stop the test process. Each order on its own is
    /// pinned — parked-first by `abandonReleasesParkedUncancellableWait`,
    /// abandoned-first by the after-the-fact call below.
    @Test("an abandoned gate releases the wait that ignores cancellation", .timeLimit(.minutes(1)))
    func abandonReleasesUncancellableWait() async {
        let gate = Gate()
        let waiter = Task { await gate.waitIgnoringCancellation() }
        gate.abandon()
        await waiter.value
        await gate.waitIgnoringCancellation()   // and at once, after the fact
    }

    /// The parked path on its own, as `abandonReleasesParkedWaiter` is for
    /// the throwing wait.
    @Test("abandoning releases a parked wait that ignores cancellation", .timeLimit(.minutes(1)))
    func abandonReleasesParkedUncancellableWait() async throws {
        let armed = Gate()
        let gate = Gate(onWaiterArmed: { armed.open() })
        let waiter = Task { await gate.waitIgnoringCancellation() }
        try await armed.wait()     // registered, so the abandon finds it parked
        gate.abandon()
        await waiter.value         // a wait left parked would wedge here until the limit
    }
}
