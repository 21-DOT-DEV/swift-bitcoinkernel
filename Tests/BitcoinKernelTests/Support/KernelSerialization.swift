//
//  KernelSerialization.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing

/// A test trait that serializes every test it is applied to against a single
/// process-wide gate, **across all files and suites**.
///
/// ### Why
///
/// libbitcoinkernel keeps process-global state — the `BCLog::Logger` singleton,
/// `cs_main`, and the global chainstate — that is not safe to touch from more
/// than one test concurrently. swift-testing runs the whole bundle in one
/// process and parallelizes by default, so two tests that each create a
/// `Context` / `ChainstateManager` (or mutate the global logger) can race and
/// hang. The built-in `.serialized` trait only serializes tests *within a single
/// suite*, so it can't coordinate the kernel-touching tests that are spread
/// across `ContextTests`, `ChainstateManagerTests`, `UpstreamConcernsTests`,
/// and friends.
///
/// This trait closes that gap with a shared ``AsyncSemaphore`` (one permit):
/// any test carrying `.kernelSerialized` waits for the gate before running and
/// releases it after, so no two ever overlap — regardless of which file or
/// suite they live in. Tests *without* the trait (pure decoders, the
/// mock-backed `BlockSource` tests, model/value types) keep running fully in
/// parallel, so this costs throughput only where correctness requires it.
///
/// The daemon integration suite is handled separately: the embedded `bitcoind`
/// holds the same global logger open for its whole lifetime, so it can't share
/// a process with kernel `LoggingConnection` tests at all and runs in its own
/// `swift test` invocation. See `.github/AGENTS.md`.
struct KernelSerializationTrait: TestTrait, SuiteTrait, TestScoping {
    /// Applied to a suite, gate each contained test (not the suite as a unit).
    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        // A suite-level invocation (testCase == nil) is a pass-through: only
        // individual test cases acquire the gate. Gating the suite itself would
        // make it hold the permit while its own tests wait on it — a deadlock.
        guard testCase != nil else {
            try await function()
            return
        }

        await Self.gate.wait()
        let result: Result<Void, any Error>
        do {
            try await function()
            result = .success(())
        } catch {
            result = .failure(error)
        }
        await Self.gate.signal()
        try result.get()
    }

    /// The one gate shared by every `.kernelSerialized` test in the process.
    private static let gate = AsyncSemaphore(value: 1)
}

extension Trait where Self == KernelSerializationTrait {
    /// Serialize this test against every other `.kernelSerialized` test in the
    /// process, across all files and suites.
    ///
    /// Apply to any test (or suite) that creates a `Context` /
    /// `ChainstateManager` or mutates the global logger. See
    /// ``KernelSerializationTrait`` for the rationale.
    static var kernelSerialized: Self { Self() }
}
