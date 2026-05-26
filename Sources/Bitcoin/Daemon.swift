//
//  Daemon.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import Synchronization
import bitcoind

private let daemonLogger = Logger(subsystem: "Bitcoin", category: "Daemon")

/// Controls the lifecycle of an embedded Bitcoin Core daemon process.
///
/// Provides static methods to start, bootstrap, and wait for the `bitcoind` process.
/// The daemon runs on a dedicated thread and communicates via JSON-RPC.
///
/// ## Typical Usage
///
/// ```swift
/// // Start the daemon
/// Daemon.start(["-regtest", "-server"])
///
/// // Bootstrap the direct RPC bridge (cookie auth — credential-free)
/// let cookieFile = dataDir.appending(path: ".cookie")
/// try await Daemon.bootstrap(cookieFile: cookieFile, port: 18443)
///
/// // Or bootstrap with explicit credentials
/// try await Daemon.bootstrap(
///     url: URL(string: "http://127.0.0.1:8332")!,
///     username: "user",
///     password: "pass"
/// )
///
/// // Now AutoTransport routes non-wallet RPCs through the direct bridge.
/// ```
public enum Daemon {
    /// Guards against concurrent or duplicate `start()` calls.
    private static let isRunning = Mutex(false)

    /// Signaled when the blocking `bitcoind_main()` call returns.
    private static let finished = DispatchSemaphore(value: 0)

    // MARK: - Start

    /// Register the RPC bridge and launch the daemon on a dedicated thread.
    /// Returns immediately.
    ///
    /// Calling `start` while a previous instance is still running logs a
    /// warning and returns without starting a second instance.
    public static func start(_ arguments: [String]) {
        let canStart = isRunning.withLock { running -> Bool in
            guard !running else { return false }
            running = true
            return true
        }
        guard canStart else {
            daemonLogger.warning("start() called while daemon is already running — ignored")
            return
        }

        // Drain any unmatched signal from a prior cycle (e.g. if
        // waitUntilStopped() was never called) to keep the semaphore
        // balanced across in-process restarts.
        while finished.wait(timeout: .now()) == .success {}

        let allArguments: [String] = ["bitcoind"] + arguments

        Thread.detachNewThread {
            // Clear the sticky g_socks5_interrupt flag left over from the
            // previous shutdown. Upstream Bitcoin Core never resets it
            // because in the normal OS-process model the process exits
            // immediately after shutdown, destroying the global. In our
            // in-process model the flag persists across invocations and
            // causes every SOCKS5 handshake on the second run to fast-fail
            // with "InterruptibleRecv() timeout or other failure".
            bitcoin_socks_reset()

            // Register the hidden "_bridge_init" RPC BEFORE bitcoind_main() starts
            // the RPC server. appendCommand aborts if called while RPC is running.
            bitcoin_rpc_register()

            // Allocate stable C strings that survive the entire bitcoind_main call.
            let argc = Int32(allArguments.count)
            let cStrings = allArguments.map { strdup($0) }
            var argv: [UnsafeMutablePointer<CChar>?] = cStrings
            argv.append(nil)
            let exitCode = argv.withUnsafeMutableBufferPointer { buf in
                bitcoind_main(argc, buf.baseAddress!)
            }
            daemonLogger.info("bitcoind_main exited with code \(exitCode)")
            cStrings.forEach { free($0) }

            isRunning.withLock { $0 = false }
            finished.signal()
        }
    }

    // MARK: - Bridge Bootstrap

    /// Bootstrap the direct RPC bridge using explicit credentials.
    ///
    /// Polls until the RPC server is ready, then calls the hidden
    /// `_bridge_init` RPC via HTTP to capture the `NodeContext` for direct
    /// dispatch. After this method returns, the auto-detecting transport
    /// inside `RPCClient(url:username:password:)` routes non-wallet RPCs
    /// through ``DirectTransport`` automatically.
    ///
    /// - Parameters:
    ///   - url: The RPC endpoint URL (e.g., `http://127.0.0.1:8332`).
    ///   - username: RPC username.
    ///   - password: RPC password.
    ///   - timeout: Maximum time to wait for the RPC server (default 30s).
    /// - Throws: The last transport error if the timeout expires, or
    ///   `CancellationError` if the task is cancelled.
    public static func bootstrap(
        url: URL,
        username: String,
        password: String,
        timeout: Duration = .seconds(30)
    ) async throws {
        let transport = HTTPTransport(url: url, username: username, password: password)
        let client = RPCClient(transport: transport)
        try await poll(timeout: timeout) {
            let _: String = try await client.send("_bridge_init")
        }
        daemonLogger.info("Direct RPC bridge activated (explicit credentials)")
    }

    /// Bootstrap the direct RPC bridge using cookie authentication.
    ///
    /// Reads the `.cookie` file written by Bitcoin Core at startup to obtain
    /// credentials, then calls `_bridge_init` via HTTP. This is the default,
    /// credential-free bootstrap mechanism.
    ///
    /// The cookie file is created during daemon startup with the format
    /// `__cookie__:<random-hex>`. This method polls for the file to appear,
    /// then uses it to authenticate the `_bridge_init` call.
    ///
    /// - Parameters:
    ///   - cookieFile: File URL to the `.cookie` file in the data directory.
    ///     For non-mainnet networks, include the network subdirectory
    ///     (e.g., `datadir/regtest/.cookie`).
    ///   - port: RPC port (default 8332).
    ///   - timeout: Maximum time to wait for the RPC server (default 30s).
    /// - Throws: The last transport or file-read error if the timeout expires,
    ///   or `CancellationError` if the task is cancelled.
    public static func bootstrap(
        cookieFile: URL,
        port: UInt16 = 8332,
        timeout: Duration = .seconds(30)
    ) async throws {
        let url = URL(string: "http://127.0.0.1:\(port)")!
        try await poll(timeout: timeout) {
            let cookie = try String(contentsOf: cookieFile, encoding: .utf8)
            let (username, password) = try Daemon.parseCookie(cookie)
            let transport = HTTPTransport(url: url, username: username, password: password)
            let client = RPCClient(transport: transport)
            let _: String = try await client.send("_bridge_init")
        }
        daemonLogger.info("Direct RPC bridge activated (cookie auth)")
    }

    // MARK: - Shutdown

    /// Block synchronously until `bitcoind_main()` has fully returned.
    ///
    /// Use this after triggering shutdown via the HTTP `"stop"` RPC.
    /// The recommended shutdown sequence for an embedded daemon is:
    ///
    /// 1. Call `bitcoin_rpc_reset()` to close the direct bridge gate.
    /// 2. Send the `"stop"` RPC via ``RPCClient`` (over HTTP).
    /// 3. Call `waitUntilStopped()` to block until `bitcoind_main()` returns.
    public static func waitUntilStopped() {
        finished.wait()
    }

    // MARK: - Internal (testable)

    /// Parses a Bitcoin Core `.cookie` file into username and password.
    ///
    /// The cookie format is `<username>:<password>` (e.g., `__cookie__:abc123hex`).
    /// Trailing whitespace (including newlines) is stripped.
    ///
    /// - Parameter contents: The raw contents of the `.cookie` file.
    /// - Returns: A tuple of `(username, password)`.
    /// - Throws: `URLError(.userAuthenticationRequired)` if the format is invalid.
    static func parseCookie(_ contents: String) throws -> (username: String, password: String) {
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }
        let parts = trimmed.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }
        return (String(parts[0]), String(parts[1]))
    }

    /// Retries `attempt` with exponential back-off until it succeeds or the deadline expires.
    ///
    /// - Parameter onWillSleep: Test-only hook fired with the planned delay
    ///   immediately before each `Task.sleep`. Lets tests assert on the delay
    ///   schedule deterministically without wall-clock measurement.
    static func poll(
        timeout: Duration,
        onWillSleep: (@Sendable (Duration) -> Void)? = nil,
        attempt: @Sendable () async throws -> Void
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        var delay: Duration = .milliseconds(250)
        let maxDelay: Duration = .seconds(2)
        var lastError: (any Error)?

        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            do {
                try await attempt()
                return
            } catch {
                lastError = error
                onWillSleep?(delay)
                try? await Task.sleep(for: delay)
                delay = min(delay * 2, maxDelay)
            }
        }
        throw lastError ?? URLError(.timedOut)
    }
}
