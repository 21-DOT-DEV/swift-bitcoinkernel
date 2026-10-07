//
//  WithHardTimeoutTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
import Clocks
import Foundation

// `withHardTimeout` lives in the shared source tree, which is compiled into
// both the NodeApp and KernelApp modules. This suite runs in both test targets,
// so the module import is picked by a per-bundle -D flag, not `canImport`:
// once NodeApp is built into a shared products dir its module is visible to
// KernelAppTests too, and `canImport(NodeApp)` would bind the wrong module.
#if NODEAPP_TESTS
@testable import NodeApp
#elseif KERNELAPP_TESTS
@testable import KernelApp
#else
#error("SharedTests compile into both test bundles, which must define NODEAPP_TESTS or KERNELAPP_TESTS")
#endif

// Every step a test takes is event-ordered through a `Gate` rather than a
// yield count or a flag sample, so a broken helper hangs a wait — which the
// `.timeLimit` then turns into a named timeout instead of a silent stall.
@Suite("withHardTimeout", .timeLimit(.minutes(1)))
struct WithHardTimeoutTests {

    /// A call that can never finish and ignores cancellation: the closest a
    /// test can get to the in-process RPC bridge this helper exists for.
    /// The gate nobody opens keeps the wait parked — and, unlike the dropped
    /// `CheckedContinuation` this replaced, a parked `Gate` wait is stored
    /// rather than leaked, so nothing prints CONTINUATION MISUSE.
    private func neverAnswers() async -> Int {
        await Gate().waitIgnoringCancellation()
        fatalError("unreachable")
    }

    @Test("a call that answers in time returns its value")
    func answersInTime() async throws {
        let clock = TestClock()
        let value = try await withHardTimeout(.seconds(30), clock: clock) { 42 }
        #expect(value == 42)
    }

    @Test("a call that throws in time reports its own error, not a timeout")
    func throwsBeforeDeadline() async {
        struct Failure: Error, Equatable {}
        let clock = TestClock()
        await #expect(throws: Failure.self) {
            try await withHardTimeout(.seconds(30), clock: clock) { () -> Int in
                throw Failure()
            }
        }
    }

    @Test("a call that never answers is abandoned when the clock runs out")
    func timeoutAbandons() async throws {
        let clock = TestClock()
        let entered = Gate()
        let task = Task {
            try await withHardTimeout(.seconds(5), clock: clock) {
                entered.open()
                return await self.neverAnswers()
            }
        }
        // `entered` is the deterministic version of what a yield count only
        // hoped for: the detached work task is provably running, so the
        // deadline was fixed on a `clock.now` that has not advanced yet.
        try await entered.wait()
        await clock.advance(by: .seconds(5))
        await #expect(throws: HardTimeoutError.self) { try await task.value }
    }

    @Test("a call that answers after the deadline is still a timeout")
    func lateAnswerIsTimeout() async throws {
        // Constructed, not scheduled: the clock is advanced a second past the
        // deadline first, *then* the call is allowed to answer — a finish
        // stamped after the deadline is a timeout no matter which task wakes
        // first.
        let clock = TestClock()
        let entered = Gate()
        let unblock = Gate()
        let task = Task {
            try await withHardTimeout(.seconds(5), clock: clock) { () -> Int in
                entered.open()
                // Parks through the courtesy cancel — it must be the test,
                // not the timeout's cancel, that lets this call answer.
                await unblock.waitIgnoringCancellation()
                return 7
            }
        }
        try await entered.wait()
        await clock.advance(by: .seconds(6))
        unblock.open()
        await #expect(throws: HardTimeoutError.self) { try await task.value }
    }

    @Test("a call that answers exactly at the deadline is late")
    func answerAtDeadlineIsLate() async throws {
        // Pins the strict `<`: within N seconds means before the deadline.
        // Advancing exactly to it before unblocking stamps the finish *at*
        // the deadline by construction.
        let clock = TestClock()
        let entered = Gate()
        let unblock = Gate()
        let task = Task {
            try await withHardTimeout(.seconds(5), clock: clock) { () -> Int in
                entered.open()
                await unblock.waitIgnoringCancellation()
                return 7
            }
        }
        try await entered.wait()
        await clock.advance(by: .seconds(5))
        unblock.open()
        await #expect(throws: HardTimeoutError.self) { try await task.value }
    }

    @Test("a call that throws CancellationError after the deadline is still a timeout")
    func lateCancelIsTimeout() async throws {
        // The mislabel the finding caught: a cancellable call answering the
        // courtesy cancel must not surface that CancellationError to the
        // caller — the honest report is that the budget ran out.
        let clock = TestClock()
        let entered = Gate()
        let task = Task {
            try await withHardTimeout(.seconds(5), clock: clock) { () -> Int in
                entered.open()
                // A gate nobody opens: `wait()` ends when the helper's
                // courtesy cancel lands, throwing CancellationError — exactly
                // the answering-call shape being pinned.
                try await Gate().wait()
                return 7
            }
        }
        try await entered.wait()
        await clock.advance(by: .seconds(5))
        await #expect(throws: HardTimeoutError.self) { try await task.value }
    }

    @Test("a timed-out call is still sent cancellation")
    func cancelStillSent() async throws {
        // The cancel is a courtesy — the in-process transport ignores it, but
        // the HTTP transport observes it, so the helper must still send it.
        let clock = TestClock()
        let entered = Gate()
        let sawCancel = Gate()
        let task = Task {
            try await withHardTimeout(.seconds(5), clock: clock) {
                await withTaskCancellationHandler {
                    entered.open()
                    return await self.neverAnswers()
                } onCancel: {
                    sawCancel.open()
                }
            }
        }
        try await entered.wait()
        await clock.advance(by: .seconds(5))
        await #expect(throws: HardTimeoutError.self) { try await task.value }
        // The assertion is the event itself: suspend until the work task's
        // cancellation handler opens the gate, whenever the executor gets to
        // it — no flag to sample ahead of its writer.
        try await sawCancel.wait()
    }

    @Test("cancelling the caller releases the wait and cancels the call")
    func callerCancelled() async throws {
        // Without this, a cancelled caller would hang on a call that ignores
        // cancellation — the suspended continuation would never resume.
        let clock = TestClock()
        let sawCancel = Gate()
        let task = Task {
            try await withHardTimeout(.seconds(30), clock: clock) {
                await withTaskCancellationHandler {
                    await self.neverAnswers()
                } onCancel: {
                    sawCancel.open()
                }
            }
        }
        // No ordering setup is needed before cancelling: a cancel delivered
        // before the detached work task even runs is sticky, and is delivered
        // whenever the call's handler installs.
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        try await sawCancel.wait()
    }

    @Test("an abandoned call still finishes in the background; its result is dropped")
    func abandonedWorkCompletes() async throws {
        let clock = TestClock()
        let entered = Gate()
        let finishWhen = Gate()
        let finished = Gate()
        let task = Task {
            try await withHardTimeout(.seconds(5), clock: clock) {
                entered.open()
                // Ignores the courtesy cancel outright — parks until the test
                // opens it, which is the point of the scenario: a call whose
                // caller has already gone away is still running.
                await finishWhen.waitIgnoringCancellation()
                finished.open()
                return 0
            }
        }
        try await entered.wait()
        await clock.advance(by: .seconds(5))
        await #expect(throws: HardTimeoutError.self) { try await task.value }
        // The helper has returned and the call has provably *not* — this is
        // positive evidence, not a timing implication.
        #expect(finished.isOpen == false)
        finishWhen.open()
        // The abandoned call now finishes, and nothing crashes when its
        // result has nowhere to go.
        try await finished.wait()
    }
}
