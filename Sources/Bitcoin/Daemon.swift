//
//  Daemon.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 Twenty Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import bitcoind
import Foundation

/// Controls the lifecycle of an embedded Bitcoin Core daemon process.
///
/// Provides static methods to start, stop, and wait for the `bitcoind` process.
/// The daemon runs on a dedicated thread and communicates via JSON-RPC.
public enum Daemon {
    /// Signaled when the blocking `bitcoind_main()` call returns.
    private static let finished = DispatchSemaphore(value: 0)

    /// Register the RPC bridge and launch the daemon on a dedicated thread.
    /// Returns immediately.
    public static func start(_ arguments: [String]) {
        let arguments: [String] = ["bitcoind"] + arguments

        Thread.detachNewThread {
            // Register the hidden "_bridge_init" RPC BEFORE bitcoind_main() starts
            // the RPC server. appendCommand aborts if called while RPC is running.
            bitcoin_rpc_register()

            // Allocate stable C strings that survive the entire bitcoind_main call.
            let argc = Int32(arguments.count)
            let cStrings = arguments.map { strdup($0) }
            var argv: [UnsafeMutablePointer<CChar>?] = cStrings
            argv.append(nil)
            let exitCode = argv.withUnsafeMutableBufferPointer { buf in
                bitcoind_main(argc, buf.baseAddress!)
            }
            print(exitCode)
            cStrings.forEach { free($0) }

            finished.signal()
        }
    }

    /// Block synchronously until `bitcoind_main()` has fully returned.
    /// Use this when shutdown has already been signaled externally (e.g. via HTTP RPC "stop").
    public static func waitUntilStopped() {
        finished.wait()
    }

    /// Signal shutdown. Returns immediately; Bitcoin Core begins tearing down.
    public static func stop() {
        bitcoin_rpc_reset()
        raise(SIGTERM)
    }

    /// Signal shutdown and wait until `bitcoind_main()` has fully returned.
    public static func stopAndWait() async {
        stop()
        await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                finished.wait()
                continuation.resume()
            }
        }
    }
}
