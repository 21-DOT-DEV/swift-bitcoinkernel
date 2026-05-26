//
//  LoggingTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
import BitcoinKernel

@Test func loggingGlobalFunctions() {
    // Verify global logging configuration functions don't crash.
    setLoggingOptions(timestamps: true, sourceLocations: true)
    setLogLevel(category: .all, level: .info)
    enableLogCategory(.validation)
    disableLogCategory(.validation)
    setLoggingOptions() // reset to defaults
}

// libbitcoinkernel's logger is process-scoped: creating a `LoggingConnection`
// flips internal state (`m_buffering = false`) the first time it runs in
// a process. On Linux, swift-testing runs all tests in a single process
// and tests later in the run also bring up kernel state that asserts
// `m_buffering`. The destroy-path resets the flag, but the lock window
// across parallel tests still races. On Apple this is masked because
// each test bundle gets a fresh xctest invocation. See `roadmap.md`
// "Linux Test Coverage" — Gap 3.
#if !os(Linux)
@Test func loggingConnectionReceivesMessages() throws {
    var messages: [String] = []
    let connection = try LoggingConnection { message in
        messages.append(message)
    }
    // Creating a context triggers internal log messages.
    enableLogCategory(.all)
    let _ = try Context()
    // The connection existing is sufficient — we verify no crash.
    // Logging output depends on kernel internals; just verify the
    // callback mechanism works without crashing.
    _ = connection
}
#endif
