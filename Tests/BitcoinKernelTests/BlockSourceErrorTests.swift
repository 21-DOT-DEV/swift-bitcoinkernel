//
//  BlockSourceErrorTests.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
import BitcoinKernel
import Foundation

// MARK: - BlockSourceError

private struct DummyError: Error {}

/// All `BlockSourceError` cases paired with a short human-readable label for
/// diagnostic output in parameterized test failures.
private let allBlockSourceErrorCases: [(label: String, error: BlockSourceError)] = [
    ("invalidResponse", .invalidResponse("bad json payload")),
    ("notFound", .notFound),
    ("notSupported", .notSupported),
    ("rateLimitedWithRetryAfter", .rateLimited(retryAfter: .seconds(5))),
    ("rateLimitedWithoutRetryAfter", .rateLimited(retryAfter: nil)),
    ("network", .network(underlying: DummyError())),
]

/// Parameterized check that every case produces a non-empty, informative
/// `localizedDescription` via the `LocalizedError` conformance.
@Test("BlockSourceError cases produce non-empty localized descriptions",
      arguments: allBlockSourceErrorCases)
func blockSourceErrorHasNonEmptyLocalizedDescription(
    label: String,
    error: BlockSourceError
) {
    #expect(!error.localizedDescription.isEmpty, "case '\(label)' produced an empty description")
}

@Test func blockSourceErrorInvalidResponseDescriptionIncludesDetail() {
    let error = BlockSourceError.invalidResponse("bad json payload")
    #expect(error.localizedDescription.contains("bad json payload"))
}

@Test func blockSourceErrorIsSendable() {
    // Compile-time check: BlockSourceError must be Sendable so it can cross
    // actor boundaries from an async BlockSource conformer.
    func requireSendable<T: Sendable>(_ value: T) {}
    requireSendable(BlockSourceError.notFound)
}
