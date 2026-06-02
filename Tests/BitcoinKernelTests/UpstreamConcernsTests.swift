//
//  UpstreamConcernsTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

//
//  UpstreamConcernsTests.swift
//
//  Investigative reproducers for libbitcoinkernel behaviors observed during
//  KernelApp Phase B2 development. Each test isolates one suspected upstream
//  concern. Some tests are intentionally **expected to fail or abort** —
//  they document the symptom so we can triage upstream filing.
//

import Testing
import BitcoinKernel
import Foundation

// MARK: - Helpers

@MainActor
private func makeRegtestContext() throws -> Context {
    let params = ChainParameters(.regtest)
    let opts = ContextOptions()
    opts.setChainParams(params)
    return try Context(options: opts)
}

@MainActor
private func makeManager(
    context: Context,
    dataDirectory: String,
    inMemory: Bool = true,
    wipeBlockTree: Bool = false,
    wipeChainstate: Bool = false
) throws -> ChainstateManager {
    let options = try ChainstateManagerOptions(context: context, dataDirectory: dataDirectory)
    if inMemory {
        options.setBlockTreeDBInMemory(true)
        options.setChainstateDBInMemory(true)
    }
    if wipeBlockTree || wipeChainstate {
        _ = options.setWipeDBs(blockTreeDB: wipeBlockTree, chainstateDB: wipeChainstate)
    }
    return try ChainstateManager(options: options)
}

private func freshTmpDir() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("UpstreamConcerns-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// MARK: - Issue 1: SIGSEGV on (true, true) wipe after prior open

/// Empirical wipe-flag matrix on **persistent** storage. The crashing
/// combination (full `(true, true)` wipe after a prior open) is NOT
/// reproduced as a test here because it would SIGSEGV the test process.
/// See bitcoin/bitcoin#35293.
///
/// | Scenario                                    | Result   |
/// |---------------------------------------------|----------|
/// | Fresh dir → `(true, true)`                  | works    |
/// | Prior open → `(false, true)` (chainstate)   | works    |
/// | Prior open → `(true, false)` (block-tree)   | works    |
/// | **Prior open → `(true, true)` (full)**      | SIGSEGV  |
@Test("Wipe matrix — all safe combinations succeed", .kernelSerialized)
func wipeMatrixSafeCombinations() async throws {
    try await MainActor.run {
        // Fresh dir + (true, true) — actually works on truly empty dir.
        let tmp = freshTmpDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let ctx = try makeRegtestContext()
        _ = try makeManager(
            context: ctx,
            dataDirectory: tmp.path,
            inMemory: false,
            wipeBlockTree: true,
            wipeChainstate: true
        )

        // Prior open → (false, true) — chainstate-only reindex.
        let tmp2 = freshTmpDir()
        defer { try? FileManager.default.removeItem(at: tmp2) }
        let ctxA = try makeRegtestContext()
        _ = try makeManager(context: ctxA, dataDirectory: tmp2.path, inMemory: false)
        let ctxB = try makeRegtestContext()
        _ = try makeManager(
            context: ctxB,
            dataDirectory: tmp2.path,
            inMemory: false,
            wipeChainstate: true
        )

        // Prior open → (true, false) — block-tree-only wipe.
        let tmp3 = freshTmpDir()
        defer { try? FileManager.default.removeItem(at: tmp3) }
        let ctxC = try makeRegtestContext()
        _ = try makeManager(context: ctxC, dataDirectory: tmp3.path, inMemory: false)
        let ctxD = try makeRegtestContext()
        _ = try makeManager(
            context: ctxD,
            dataDirectory: tmp3.path,
            inMemory: false,
            wipeBlockTree: true
        )
    }
}

// MARK: - Hypothesis 2 (rejected): rapid create-destroy-create cycles

/// **Hypothesis (REJECTED 2026-05-03)**: libbitcoinkernel might have
/// process-global state that breaks on repeated `Context` /
/// `ChainstateManager` create-destroy cycles (analogous to bitcoind's
/// `g_shutdown` / `gArgs` issue documented in `patches/bitcoin/shutdown-reset.md`).
///
/// Result: 5 sequential cycles work fine — kept here as a regression
/// guard in case future libbitcoinkernel changes regress this property.
@Test("Five rapid Context+ChainstateManager create/destroy cycles in one process", .kernelSerialized)
func repeatedKernelLifecycle() async throws {
    for i in 0..<5 {
        let tmpDir = freshTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try await MainActor.run {
            let context = try makeRegtestContext()
            let manager = try makeManager(
                context: context,
                dataDirectory: tmpDir.path,
                inMemory: true
            )
            #expect(manager.bestEntry.height == 0, "cycle \(i)")
            // Drop references at scope end → deinit should clean up.
        }
    }
}

// MARK: - Issue 1 crashing reproducer (opt-in, Xcode-only)

/// **Reproducer for [bitcoin/bitcoin#35293](https://github.com/bitcoin/bitcoin/issues/35293)**.
///
/// Disabled by default because it kills the test process. Failure mode
/// depends on which fix layer is in place:
///
/// - **Pre-X2 (raw libbitcoinkernel)**: SIGSEGV in
///   `btck_block_tree_entry_get_height` (null-deref in C).
/// - **Post-X2 (Swift wrapper trap, current)**: `preconditionFailure`
///   from `ChainstateManager.bestEntry` with a diagnostic message
///   pointing at this issue file.
/// - **Post-upstream Option A (genesis bootstrapped on construction)**:
///   no crash; `bestEntry` returns the genesis entry.
///
/// ### What actually fails
///
/// The second `ChainstateManager.init` **succeeds** silently.
/// `btck_chainstate_manager_get_best_entry` then returns `nullptr`
/// because `chainman.m_best_header` is null right after a `(true, true)`
/// wipe (genesis is not auto-loaded). The downstream accessors
/// (`btck_block_tree_entry_get_height` etc.) don't null-guard the entry
/// pointer.
///
/// ### Trigger conditions (all required)
///
/// 1. First `ChainstateManager` opens against the data dir (no wipe).
/// 2. First manager's `bestEntry` is accessed — materializes block-index
///    state on disk so the wipe target is non-empty.
/// 3. First manager deinits.
/// 4. Second `ChainstateManager` opens with
///    `setWipeDBs(blockTreeDB: true, chainstateDB: true)`.
/// 5. **Accessing `bestEntry` on the second manager** — traps in the
///    Swift wrapper post-X2, or SEGVs at the C layer pre-X2.
///
/// ### To capture a symbolicated stack trace in Xcode
///
/// 1. Open `Package.swift` in Xcode (or the workspace).
/// 2. Product → Scheme → pick a scheme exposing `BitcoinKernelTests`.
/// 3. Comment out the `.disabled(...)` trait below.
/// 4. Set a breakpoint on the `try ChainstateManager(options: mopts2)`
///    line below (optional — lets you step into the C call).
/// 5. Right-click the test in the Test Navigator → "Run …".
/// 6. On SIGSEGV, Xcode pauses in the Debug Navigator. The call stack on
///    the left pane is already symbolicated; `bt all` in the LLDB console
///    prints every thread.
/// 7. Copy the stack into bitcoin/bitcoin#35293, then restore
///    `.disabled(...)` before committing.
@Test(
    "CRASH — (true, true) wipe + bestEntry access traps (post-X2) / SIGSEGVs (pre-X2)",
    .tags(.exitTest),
    .disabled("Kills the test process via Swift preconditionFailure (post-X2) or SIGSEGV (pre-X2). Enable only in Xcode for diagnosis.")
)
func captureSegfaultForUpstream() throws {
    let tmpDir = freshTmpDir()
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    // Helper that opens, accesses bestEntry (critical!), and returns.
    // Without `bestEntry.height` access this whole sequence completes
    // successfully — the access materializes chainstate state on disk
    // that the subsequent (true, true) wipe can't safely rebuild.
    func openOnce(wipeAll: Bool) throws -> Int32 {
        let params = ChainParameters(.regtest)
        let opts = ContextOptions()
        opts.setChainParams(params)
        let ctx = try Context(options: opts)
        let mopts = try ChainstateManagerOptions(context: ctx, dataDirectory: tmpDir.path)
        if wipeAll {
            _ = mopts.setWipeDBs(blockTreeDB: true, chainstateDB: true)
        }
        let mgr = try ChainstateManager(options: mopts)
        return mgr.bestEntry.height
    }

    _ = try openOnce(wipeAll: false)
    // SIGSEGV inside `ChainstateManager.init` on the second call.
    _ = try openOnce(wipeAll: true)
    // If execution reaches here, upstream may have fixed the bug.
}

// MARK: - Issue 1 recovery: documented wipe → importBlocks lifecycle

/// Demonstrates the recovery path that bitcoin/bitcoin#35304 documents and
/// that issue https://github.com/bitcoin/bitcoin/issues/35293 is about:
/// after a `(true, true)` wipe leaves `m_best_header` null, calling
/// `importBlocks(from: [])` completes the reindex and re-activates genesis,
/// so `bestEntry` is observable again without trapping.
///
/// This is the same trigger sequence as `captureSegfaultForUpstream`, with the
/// documented `importBlocks(from: [])` recovery inserted before the second
/// `bestEntry` access. Uses persistent storage because the bug only manifests
/// against an on-disk block tree.
@Test("Wipe (true,true) recovers via importBlocks(from: []) before bestEntry", .kernelSerialized)
func wipeThenImportBlocksRecoversBestEntry() async throws {
    let tmpDir = freshTmpDir()
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    // First open (persistent, no wipe). Accessing bestEntry materializes the
    // on-disk block-index state that makes the later (true, true) wipe leave
    // m_best_header null.
    try await MainActor.run {
        let ctx = try makeRegtestContext()
        let mgr = try makeManager(context: ctx, dataDirectory: tmpDir.path, inMemory: false)
        #expect(mgr.bestEntry.height == 0)
    }

    // Reopen with full wipe, then run the documented recovery before reading
    // bestEntry. If empty-list import re-activates genesis, this does not trap.
    try await MainActor.run {
        let ctx = try makeRegtestContext()
        let mgr = try makeManager(
            context: ctx,
            dataDirectory: tmpDir.path,
            inMemory: false,
            wipeBlockTree: true,
            wipeChainstate: true
        )
        #expect(mgr.importBlocks(from: []), "empty-list import (reindex completion) should succeed")
        #expect(mgr.bestEntry.height == 0, "bestEntry should be observable after reindex completion")
    }
}

// MARK: - Issue 1 safety: skipping recovery traps (not SEGV), citing #35293

/// Exit test: if a caller does the `(true, true)` wipe but skips the
/// `importBlocks(from: [])` recovery and reads `bestEntry`, the wrapper must
/// trap with a diagnostic (Swift `preconditionFailure`) rather than SEGV in the
/// C accessor. Asserts the child process exits abnormally and that the emitted
/// message points at https://github.com/bitcoin/bitcoin/issues/35293 so a stuck
/// user can find the explanation.
///
/// Runs in a spawned subprocess, so the trap does not kill the test runner.
/// This is the enabled counterpart to the opt-in `captureSegfaultForUpstream`.
@Test("Skipping importBlocks recovery traps with a #35293 diagnostic",
      .tags(.exitTest),
      .enabled(if: ProcessInfo.processInfo.environment["RUN_EXIT_TESTS"] != nil))
func bestEntryTrapsWhenRecoverySkipped() async throws {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        // Same trigger as captureSegfaultForUpstream: a prior open whose
        // bestEntry access materializes on-disk state, then a (true, true)
        // wipe, then bestEntry WITHOUT the importBlocks recovery.
        func openOnce(wipeAll: Bool) throws -> Int32 {
            let params = ChainParameters(.regtest)
            let opts = ContextOptions()
            opts.setChainParams(params)
            let ctx = try Context(options: opts)
            let mopts = try ChainstateManagerOptions(context: ctx, dataDirectory: tmp.path)
            if wipeAll { _ = mopts.setWipeDBs(blockTreeDB: true, chainstateDB: true) }
            let mgr = try ChainstateManager(options: mopts)
            return mgr.bestEntry.height
        }

        _ = try openOnce(wipeAll: false)
        _ = try openOnce(wipeAll: true)  // bestEntry trap fires here
    }

    // The diagnostic must name the upstream issue.
    if let stderrBytes = result?.standardErrorContent {
        let message = String(decoding: stderrBytes, as: UTF8.self)
        #expect(message.contains("35293"), "trap message should cite issue #35293")
    }
}

// MARK: - Hypothesis 3 (rejected): deinit after data directory removed

/// **Hypothesis (REJECTED 2026-05-03)**: `ChainstateManager.deinit` might
/// crash if the data dir was removed while the manager was alive.
///
/// Result: deinit is graceful — kept as a regression guard.
@Test("Manager deinit after data directory removed — persistent storage", .kernelSerialized)
func managerDeinitAfterDirRemoved() async throws {
    let tmpDir = freshTmpDir()

    try await MainActor.run {
        let context = try makeRegtestContext()
        let manager = try makeManager(
            context: context,
            dataDirectory: tmpDir.path,
            inMemory: false
        )
        #expect(manager.bestEntry.height == 0)

        // Remove the directory while the manager still holds open file
        // handles. On Apple platforms the inodes survive until close, but
        // any LevelDB *write* attempt against a missing dir fails.
        try? FileManager.default.removeItem(at: tmpDir)

        // Manager and context dealloc at scope end. If deinit triggers a
        // LevelDB flush to the missing dir, this scope exit aborts.
        _ = manager
    }
}

// MARK: - Issue 4 candidate: in-memory + create-destroy cycles

/// In-memory variant of issue 2. If hypothesis 2 is about persistent
/// LevelDB state, in-memory should work. If it's about process-global
/// kernel state (logger, signal handlers, etc.), even in-memory will
/// break.
@Test("Five in-memory kernel cycles — should succeed if global state is clean", .kernelSerialized)
func repeatedKernelLifecycleInMemoryOnly() async throws {
    for i in 0..<5 {
        let tmpDir = freshTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try await MainActor.run {
            let context = try makeRegtestContext()
            _ = try makeManager(
                context: context,
                dataDirectory: tmpDir.path,
                inMemory: true
            )
            // bestEntry intentionally not asked for — minimize work.
            _ = i
        }
    }
}
