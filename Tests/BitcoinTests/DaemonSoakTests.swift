//
//  DaemonSoakTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
import Foundation
import Bitcoin
import bitcoind

// MARK: - In-process restart soak

/// Drives several `Daemon.start` → bootstrap → `stop` → `waitUntilStopped`
/// cycles in a single process to prove the in-process-restart patches
/// (`patches/bitcoin/{rpc-server-reset,shutdown-reset}`) hold up: a second
/// and later `bitcoind_main()` must not trip the process-global asserts.
///
/// Gated behind `RUN_SOAK_TESTS=1` and run alone so it owns the one daemon a
/// process may host:
///
///     RUN_SOAK_TESTS=1 swift test --filter 'BitcoinTests.DaemonSoakTests'
@Suite(
    "Daemon In-Process Restart Soak",
    .enabled(if: ProcessInfo.processInfo.environment["RUN_SOAK_TESTS"] == "1")
)
struct DaemonSoakTests {

    @Test("repeated start/stop cycles leave the daemon cleanly stopped each time")
    func restartCycles() async throws {
        let dataDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("soak-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dataDir) }

        let cookie = dataDir.appendingPathComponent("cookie")
        let port: UInt16 = 18443
        let endpoint = URL(string: "http://127.0.0.1:\(port)")!

        let arguments = BitcoinConfig.regtest()
            .server()
            .rpcBind(.localhost)
            .rpcAllowIP(.localhost)
            .rpcPort(port)
            .rpcCookieFile(cookie.path)
            .dataDir(dataDir.path(percentEncoded: false))
            .arguments

        for cycle in 1...5 {
            Daemon.start(arguments)
            try await Daemon.bootstrap(cookieFile: cookie, port: port, timeout: .seconds(30))

            let client = RPCClient(url: endpoint, cookieFile: cookie)
            let info = try await client.getBlockchainInfo()
            #expect(info.chain == "regtest", "cycle \(cycle): wrong chain")

            // Mirror NodeViewModel.performStop()'s shutdown sequence.
            bitcoin_rpc_reset()
            _ = try? await client.stop()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                Thread.detachNewThread {
                    Daemon.waitUntilStopped()
                    continuation.resume()
                }
            }
        }
    }
}
