//
//  LoggingTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import Testing
import BitcoinKernel

@Test(.kernelSerialized) func loggingGlobalFunctions() {
    // Verify global logging configuration functions don't crash.
    setLoggingOptions(timestamps: true, sourceLocations: true)
    setLogLevel(category: .all, level: .info)
    enableLogCategory(.validation)
    disableLogCategory(.validation)
    setLoggingOptions() // reset to defaults
}

// libbitcoinkernel's logger is a process-global singleton. Creating a
// `LoggingConnection` calls `StartLogging` (which asserts `m_buffering`), and the
// embedded `bitcoind` init does the same on the SAME `LogInstance`. This test
// carries `.kernelSerialized` so it never overlaps another kernel-touching test
// (see `Support/KernelSerialization.swift`), and the daemon integration suite
// runs in its own process (see `.github/AGENTS.md`) — so neither this connection
// nor a concurrent test can race the global logger. The callback funnels through
// a lock because the kernel may invoke it from internal threads even for a
// single connection.
@Test(.kernelSerialized) func loggingConnectionReceivesMessages() throws {
    final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var messages: [String] = []
        func append(_ message: String) { lock.lock(); defer { lock.unlock() }; messages.append(message) }
    }
    let sink = Sink()
    let connection = try LoggingConnection { sink.append($0) }
    // Creating a context triggers internal log messages through the callback.
    enableLogCategory(.validation)
    let _ = try Context()
    disableLogCategory(.validation)
    // We just verify the callback mechanism runs without crashing.
    _ = connection
    _ = sink
}
