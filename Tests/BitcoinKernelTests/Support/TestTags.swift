//
//  TestTags.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing

extension Tag {
    /// Marks Swift Testing exit tests (`#expect(processExitsWith:)`), which spawn
    /// a child process per test.
    ///
    /// Exit tests can't run under the parallel runner (the spawn hangs amid the
    /// pool) and can't be isolated with `--filter` (the child re-enters the
    /// filtered run and recurses, which SE-0008 forbids). So every exit test is
    /// also gated with `.enabled(if: ProcessInfo…environment["RUN_EXIT_TESTS"])`
    /// and runs on demand via `RUN_EXIT_TESTS=1 swift test --no-parallel`. This
    /// tag is the semantic marker (and enables `xcodebuild -skip-testing-tags`);
    /// the `.enabled(if:)` gate is what actually keeps them out of normal CI.
    /// See `.github/AGENTS.md`.
    @Tag static var exitTest: Self
}
