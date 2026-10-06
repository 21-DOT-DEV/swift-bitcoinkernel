//
//  VolatileDefaults.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Returns an empty ``UserDefaults`` for one test — a scratch suite, never the
/// app's real store.
///
/// A hosted test bundle shares the app's `UserDefaults.standard` domain, so a
/// test that writes it mutates the person's real settings (an earlier suite
/// deleted keys like `bitcoin_network` and `tor_enabled` as its per-test
/// "reset"). The suite is named after the calling test — module, file, and
/// function — so separate tests never share a store, while repeated runs reuse
/// the same suite rather than piling a new `dev.21.tests.*` plist into the app
/// container's `Library/Preferences` on every invocation.
/// `removePersistentDomain` clears whatever an earlier run left behind.
///
/// Two cautions fall out of the name coming from the call site:
///
/// - A helper wrapping this must declare the same defaulted parameters and
///   forward them — its own `#fileID`/`#function` otherwise resolve inside the
///   helper and every test through it shares one store:
///   `helper(fileID: String = #fileID, function: String = #function)` →
///   `makeVolatileDefaults(fileID: fileID, function: function)`.
/// - `@Test(arguments:)` cases share one call site and can run in parallel,
///   so each case must pass a `distinguisher` (e.g. `"\(argument)"`) or the
///   cases share — and keep wiping — one store. The same escape covers two
///   same-named tests in one file. An overlong distinguisher is truncated and
///   hashed, so the suite name stays well under the 255-byte filename limit —
///   writes into an overlong name would fail silently and the test would read
///   back nothing.
///
/// The matching production-side seam is a `UserDefaults` parameter defaulting
/// to `.standard` — the shape `DaemonConfig.Snapshot(reading:)` and
/// `KernelAppSettings(defaults:)` already use.
func makeVolatileDefaults(
    fileID: String = #fileID,
    function: String = #function,
    distinguisher: String? = nil
) -> UserDefaults {
    let scope = fileID
        .replacingOccurrences(of: "/", with: ".")
        .replacingOccurrences(of: ".swift", with: "")
    let suffix = distinguisher.map { raw -> String in
        let cleaned = raw.replacingOccurrences(of: "/", with: "-")
        guard cleaned.utf8.count > 64 else { return "." + cleaned }
        let head = String(decoding: cleaned.utf8.prefix(48), as: UTF8.self)
        return "." + head + "-" + String(fnv1a(cleaned), radix: 16)
    } ?? ""
    let suiteName = "dev.21.tests.\(scope).\(function)\(suffix)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// FNV-1a — a stable 64-bit digest for overlong distinguishers. `hashValue`
/// can't serve: it is seeded per-process, so it would mint a new suite per run
/// and recreate the plist pile-up the naming exists to avoid.
private func fnv1a(_ string: String) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in string.utf8 {
        hash = (hash ^ UInt64(byte)) &* 0x100000001b3
    }
    return hash
}
