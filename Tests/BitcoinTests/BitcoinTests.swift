//
//  BitcoinTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
import Bitcoin
import bitcoind
import Foundation

// MARK: - Shared Daemon Fixture

/// Manages the Bitcoin daemon lifecycle for integration tests.
///
/// The daemon starts exactly once across all tests via `startOnce`, and is
/// stopped gracefully via an `atexit` handler registered by `shutdownOnce`.
/// Both are triggered by `ensureRunning()` which each test suite calls from
/// its `init()`.
private enum DaemonFixture {
    static let port: UInt16 = 8332

    static var cookieFileURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bitcoin-test-rpc.cookie")
    }

    private static let startOnce: Void = {
        // Cookie auth — no hardcoded credentials. Bitcoin Core writes the
        // cookie at the path we specify via -rpccookiefile.
        try! Daemon.start(with:
            BitcoinConfig.mainnet()
                .server()
                .rpcBind(.allInterfaces)
                .rpcAllowIP(.localhost)
                .rpcPort(port)
                .rpcCookieFile(cookieFileURL.path)
                .prune(.minimum)
                .blockFilterIndex(.all)
        )

        // Bootstrap the direct RPC bridge using cookie authentication.
        // Deterministic polling — returns as soon as the RPC server is
        // ready, then activates the direct bridge via _bridge_init.
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            try! await Daemon.bootstrap(
                cookieFile: cookieFileURL,
                port: port
            )
            semaphore.signal()
        }
        semaphore.wait()
    }()

    /// Registers a one-time atexit handler that gracefully shuts down the
    /// daemon so the process exits cleanly.
    private static let shutdownOnce: Void = {
        atexit {
            let client = DaemonFixture.makeClient()
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                _ = try? await client.stop()
                semaphore.signal()
            }
            semaphore.wait()
            Daemon.waitUntilStopped()
        }
    }()

    static func ensureRunning() {
        _ = startOnce
        _ = shutdownOnce
    }

    static func makeClient() -> RPCClient {
        RPCClient(
            url: URL(string: "http://localhost:\(port)")!,
            cookieFile: cookieFileURL
        )
    }
}

// MARK: - Bitcoin Integration Tests

@Suite("Bitcoin Integration", .serialized)
final class BitcoinTests {

    init() {
        DaemonFixture.ensureRunning()
    }

    @Test("Direct RPC bridge is active after bootstrap")
    func directBridgeActive() {
        #expect(bitcoin_rpc_ready() == 1, "Direct bridge should be active after bootstrap")
    }

    @Test("getBlockVerbose returns genesis block")
    func getGenesisBlock() async throws {
        let client = DaemonFixture.makeClient()
        let block = try await client.getBlockVerbose(
            hash: "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"
        )
        #expect(block.height == 0)
    }
}
