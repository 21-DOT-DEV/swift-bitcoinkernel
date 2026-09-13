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
import Synchronization

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

@Suite("withHardTimeout")
struct WithHardTimeoutTests {

    /// The helper spawns its work and timer as detached tasks, so there is a
    /// scheduling gap between starting a call and the timer registering its
    /// sleep with the `TestClock`. Advancing before that registration would
    /// fire nothing and hang the test; a handful of yields closes the gap
    /// (the same pattern `KernelAppViewModelTests` uses).
    private func settle() async {
        for _ in 1...10 { await Task.yield() }
    }

    /// A call that can never finish and ignores cancellation: the closest a
    /// test can get to the in-process RPC bridge this helper exists for.
    private func neverAnswers() async -> Int {
        await withCheckedContinuation { (_: CheckedContinuation<Int, Never>) in }
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
        let task = Task {
            try await withHardTimeout(.seconds(5), clock: clock) {
                await self.neverAnswers()
            }
        }
        await settle()
        await clock.advance(by: .seconds(5))
        await #expect(throws: HardTimeoutError.self) { try await task.value }
    }

    @Test("a call that answers after the deadline is still a timeout")
    func lateAnswerIsTimeout() async throws {
        // The race the deadline check exists for: one advance makes the call's
        // sleep and the timer's sleep due together. Whichever wakes first must
        // not matter — the call finished past its budget.
        let clock = TestClock()
        let task = Task {
            try await withHardTimeout(.seconds(5), clock: clock) { () -> Int in
                // `try?` so the courtesy cancel can't end this call early.
                try? await clock.sleep(for: .seconds(10))
                return 7
            }
        }
        await settle()
        await clock.advance(by: .seconds(10))
        await #expect(throws: HardTimeoutError.self) { try await task.value }
    }

    @Test("a call that answers exactly at the deadline is late")
    func answerAtDeadlineIsLate() async throws {
        // Pins the strict `<`: within N seconds means before the deadline.
        let clock = TestClock()
        let task = Task {
            try await withHardTimeout(.seconds(5), clock: clock) { () -> Int in
                try? await clock.sleep(for: .seconds(5))
                return 7
            }
        }
        await settle()
        await clock.advance(by: .seconds(5))
        await #expect(throws: HardTimeoutError.self) { try await task.value }
    }

    @Test("a call that throws CancellationError after the deadline is still a timeout")
    func lateCancelIsTimeout() async throws {
        // The mislabel the finding caught: a cancellable call answering the
        // courtesy cancel must not surface that CancellationError to the
        // caller — the honest report is that the budget ran out.
        let clock = TestClock()
        let task = Task {
            try await withHardTimeout(.seconds(5), clock: clock) { () -> Int in
                try await clock.sleep(for: .seconds(10))
                return 7
            }
        }
        await settle()
        await clock.advance(by: .seconds(10))
        await #expect(throws: HardTimeoutError.self) { try await task.value }
    }

    @Test("a timed-out call is still sent cancellation")
    func cancelStillSent() async throws {
        // The cancel is a courtesy — the in-process transport ignores it, but
        // the HTTP transport observes it, so the helper must still send it.
        let clock = TestClock()
        let sawCancel = Mutex(false)
        let task = Task {
            try await withHardTimeout(.seconds(5), clock: clock) {
                await withTaskCancellationHandler {
                    await self.neverAnswers()
                } onCancel: {
                    sawCancel.withLock { $0 = true }
                }
            }
        }
        await settle()
        await clock.advance(by: .seconds(5))
        await #expect(throws: HardTimeoutError.self) { try await task.value }
        #expect(sawCancel.withLock { $0 })
    }

    @Test("cancelling the caller releases the wait and cancels the call")
    func callerCancelled() async throws {
        // Without this, a cancelled caller would hang on a call that ignores
        // cancellation — the suspended continuation would never resume.
        let clock = TestClock()
        let sawCancel = Mutex(false)
        let task = Task {
            try await withHardTimeout(.seconds(30), clock: clock) {
                await withTaskCancellationHandler {
                    await self.neverAnswers()
                } onCancel: {
                    sawCancel.withLock { $0 = true }
                }
            }
        }
        await settle()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(sawCancel.withLock { $0 })
    }

    @Test("an abandoned call still finishes in the background; its result is dropped")
    func abandonedWorkCompletes() async throws {
        let clock = TestClock()
        let finished = Mutex(false)
        let task = Task {
            try await withHardTimeout(.seconds(5), clock: clock) {
                await withTaskCancellationHandler {
                    // Cancellation-resistant work: `try?` swallows the cancel
                    // sent at timeout, so this resumes only when its own (later)
                    // sleep elapses — or when cancelled twice by the caller.
                    try? await Task.sleep(for: .seconds(10), clock: clock)
                } onCancel: {}
                if Task.isCancelled {
                    // The courtesy cancel landed; simulate work that ignores it
                    // and runs to completion anyway.
                    try? await Task.sleep(for: .seconds(10), clock: clock)
                }
                finished.withLock { $0 = true }
                return 0
            }
        }
        await settle()
        await clock.advance(by: .seconds(5))
        await #expect(throws: HardTimeoutError.self) { try await task.value }
        // The helper has returned; the call has not finished. It does later,
        // and nothing crashes when its result has nowhere to go.
        await clock.advance(by: .seconds(10))
        await settle()
        #expect(finished.withLock { $0 })
    }
}
