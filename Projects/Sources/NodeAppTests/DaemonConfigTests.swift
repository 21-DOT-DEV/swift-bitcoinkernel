//
//  DaemonConfigTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
import Foundation
@testable import NodeApp

// Argument-level behaviour is already pinned by `BuildArgumentsTests` through the
// live-read entry point; this suite covers what is new — the snapshot mapping
// itself, and that a handed-in snapshot is what the builder consults.
@Suite("DaemonConfig.Snapshot")
struct DaemonConfigTests {

    /// A scratch defaults suite, so no test reads or leaves the app's real
    /// settings. Named per test because suites run in parallel and a shared one
    /// would race.
    private func suite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("the snapshot freezes every setting the argument builder consults")
    func snapshotReadsAllKeys() {
        let defaults = suite("DaemonConfigTests.snapshotReadsAllKeys")
        defer { defaults.removePersistentDomain(forName: "DaemonConfigTests.snapshotReadsAllKeys") }

        defaults.set("Signet", forKey: "bitcoin_network")
        defaults.set("Archival", forKey: "node_type")
        defaults.set(512.0, forKey: "prune_size_mb")
        defaults.set(true, forKey: "tor_enabled")
        defaults.set(true, forKey: "private_broadcast_enabled")
        defaults.set(450.0, forKey: "max_mempool_mb")
        defaults.set(60.0, forKey: "max_connections")
        defaults.set(false, forKey: "listen_enabled")
        defaults.set("user:hash", forKey: "rpc_auth")

        let snapshot = DaemonConfig.Snapshot(reading: defaults)
        #expect(snapshot.network == .signet)
        #expect(snapshot.nodeType == .archival)
        #expect(snapshot.pruneSizeMB == 512)
        #expect(snapshot.torEnabled)
        #expect(snapshot.privateBroadcastEnabled)
        #expect(snapshot.maxMempoolMB == 450)
        #expect(snapshot.maxConnections == 60)
        #expect(snapshot.listenEnabled == false)
        #expect(snapshot.rpcAuth == "user:hash")
    }

    @Test("keys that were never set read as the app's fallbacks")
    func snapshotFallbacks() {
        let defaults = suite("DaemonConfigTests.snapshotFallbacks")
        defer { defaults.removePersistentDomain(forName: "DaemonConfigTests.snapshotFallbacks") }

        let snapshot = DaemonConfig.Snapshot(reading: defaults)
        #expect(snapshot.network == .mainnet)
        #expect(snapshot.nodeType == .pruned)
        #expect(snapshot.torEnabled == false)
        #expect(snapshot.privateBroadcastEnabled == false)
        // "Unset" is carried through for listen, distinct from "on": only an
        // explicit false earns a `-listen=0`, so conflating them would emit a
        // flag the person never set.
        #expect(snapshot.listenEnabled == nil)
        #expect(snapshot.rpcAuth.isEmpty)
    }

    @Test("arguments come from the snapshot handed in, not the store")
    func argumentsFromSnapshot() {
        let defaults = suite("DaemonConfigTests.argumentsFromSnapshot")
        defer { defaults.removePersistentDomain(forName: "DaemonConfigTests.argumentsFromSnapshot") }

        // A snapshot whose values no live read could currently produce must
        // still be the one consulted — this is the whole point of passing it in.
        var snapshot = DaemonConfig.Snapshot(reading: defaults)
        snapshot.network = .signet
        snapshot.torEnabled = true
        snapshot.privateBroadcastEnabled = true

        let args = DaemonConfig.buildArguments(settings: snapshot, torProxy: "127.0.0.1:9050")
        #expect(args.contains("-signet"))
        #expect(args.contains("-proxy=127.0.0.1:9050"))
        #expect(args.contains("-privatebroadcast=1"))
        // The other networks' flags are the ones a misread store could emit;
        // mainnet has no flag at all, so only the real ones are worth denying.
        #expect(args.contains("-testnet") == false)
        #expect(args.contains("-regtest") == false)
    }
}
