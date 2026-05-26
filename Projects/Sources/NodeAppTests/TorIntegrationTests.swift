//
//  TorIntegrationTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2022-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import Testing
import Tor

// MARK: - Tor Integration Tests

@Suite("Tor Integration", .serialized)
struct TorIntegrationTests {

    @Test("Full Tor lifecycle: start → bootstrap → endpoint → stop",
          .timeLimit(.minutes(3)),
          .disabled("Requires network access — run manually"))
    func fullLifecycle() async throws {
        // Use ephemeral() so the temp data directory is auto-cleaned on stop.
        let client = TorClient(configuration: .ephemeral())
        try await client.start()

        try await client.waitUntilBootstrapped()

        let endpoint = await client.socksEndpoint
        #expect(endpoint != nil, "SOCKS endpoint should be available after bootstrap")
        #expect(endpoint!.port > 0, "SOCKS port should be a valid port number")
        #expect(endpoint!.host == "127.0.0.1", "SOCKS host should be localhost")

        await client.stop()
    }
}
