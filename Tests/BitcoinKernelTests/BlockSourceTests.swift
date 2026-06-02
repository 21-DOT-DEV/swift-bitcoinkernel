//
//  BlockSourceTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
import BitcoinKernel
import Foundation

// MARK: - URL accessors

@Test func urlAccessorsPointAtExpectedPaths() {
    #expect(URL.mempoolSpaceMainnet.absoluteString == "https://mempool.space/api")
    #expect(URL.mempoolSpaceTestnet.absoluteString == "https://mempool.space/testnet/api")
    #expect(URL.mempoolSpaceTestnet4.absoluteString == "https://mempool.space/testnet4/api")
    #expect(URL.mempoolSpaceSignet.absoluteString == "https://mempool.space/signet/api")
    #expect(URL.blockstreamInfo.absoluteString == "https://blockstream.info/api")
    #expect(URL.blockstreamInfoTestnet.absoluteString == "https://blockstream.info/testnet/api")
}

// The tests below drive `EsploraBlockSource` through `MockHTTPClient`, an
// in-memory `HTTPDataFetching` double: no `URLProtocol`, no `URLSession`, and no
// network. They're deterministic and parallel-safe, and they run on every
// platform — including Linux, where `URLProtocol` interception is a no-op.

// MARK: - Helpers

/// Tip of Signet near height 210k, hex form as Esplora serves it (display order).
private let sampleBlockHashDisplayHex =
    "00000000000000000001a3bb48a04df6dd6e48ea74d30ba59be6b6c9a4e85d5e"

/// Build a source wired to a `MockHTTPClient`, using short delays so retry/backoff
/// and pacing tests complete quickly without sacrificing coverage.
private func makeSource(
    client: MockHTTPClient,
    minimumInterRequestDelay: Duration = .milliseconds(50),
    maximumRetries: Int = 5,
    baseRetryDelay: Duration = .milliseconds(10)
) -> EsploraBlockSource {
    EsploraBlockSource(
        endpoint: client.baseURL,
        httpClient: client,
        minimumInterRequestDelay: minimumInterRequestDelay,
        maximumRetries: maximumRetries,
        baseRetryDelay: baseRetryDelay
    )
}

// MARK: - Parsing / happy path

@Test func bestTipParsesHeightFromTextResponse() async throws {
    let client = MockHTTPClient()
    client.enqueue(.ok(body: "800000"))
    client.enqueue(.ok(body: sampleBlockHashDisplayHex))

    let source = makeSource(client: client)
    let tip = try await source.bestTip()

    #expect(tip.height == 800_000)
    #expect(tip.hash.count == 32)
    // Hash is stored in internal (kernel) order — reversed from display hex.
    let displayBytes = dataFromHex(sampleBlockHashDisplayHex)
    #expect(tip.hash == Data(displayBytes.reversed()))
    #expect(tip.timestamp == nil)
    // Exactly two requests: height, then hash.
    #expect(client.records.count == 2)
    #expect(client.records[0].url.path.hasSuffix("/blocks/tip/height"))
    #expect(client.records[1].url.path.hasSuffix("/blocks/tip/hash"))
}

@Test func blockHashAtHeightParsesHex() async throws {
    let client = MockHTTPClient()
    client.enqueue(.ok(body: sampleBlockHashDisplayHex))

    let source = makeSource(client: client)
    let hash = try await source.blockHash(atHeight: 123_456)

    #expect(hash.count == 32)
    let displayBytes = dataFromHex(sampleBlockHashDisplayHex)
    #expect(hash == Data(displayBytes.reversed()))
    #expect(client.records.first?.url.path.hasSuffix("/block-height/123456") == true)
}

@Test func blockHeaderParsesHexBytes() async throws {
    let client = MockHTTPClient()
    // Esplora returns the 80-byte header as 160 hex chars (ASCII text body).
    client.enqueue(.ok(body: genesisHeaderHex))

    let source = makeSource(client: client)
    let hashInternal = dataFromHex(genesisBlockHashHex)
    let header = try await source.blockHeader(for: hashInternal)

    #expect(header.version == 1)
    #expect(header.timestamp == 1231006505)
    #expect(header.bits == 0x1d00ffff)
    #expect(header.nonce == 2083236893)
    // URL path must embed the display-order hex (reversed from internal).
    let displayHex = Data(hashInternal.reversed()).map { String(format: "%02x", $0) }.joined()
    #expect(client.records.first?.url.path.hasSuffix("/block/\(displayHex)/header") == true)
}

@Test func blockParsesRawBinary() async throws {
    let client = MockHTTPClient()
    client.enqueue(.ok(data: dataFromHex(genesisBlockHex)))

    let source = makeSource(client: client)
    let hashInternal = dataFromHex(genesisBlockHashHex)
    let block = try await source.block(for: hashInternal)

    #expect(block.transactionCount == 1)
    let displayHex = Data(hashInternal.reversed()).map { String(format: "%02x", $0) }.joined()
    #expect(client.records.first?.url.path.hasSuffix("/block/\(displayHex)/raw") == true)
}

// MARK: - Error mapping

@Test func bestTipFailsOnNonNumericHeight() async {
    let client = MockHTTPClient()
    client.enqueue(.ok(body: "not-a-number"))

    let source = makeSource(client: client)
    await #expect(throws: BlockSourceError.self) {
        _ = try await source.bestTip()
    }
}

@Test func blockFailsOnCorruptedBody() async {
    let client = MockHTTPClient()
    // Random 100 bytes — not a valid consensus-encoded block.
    client.enqueue(.ok(data: Data((0..<100).map { UInt8($0 & 0xFF) })))

    let source = makeSource(client: client)
    let hashInternal = dataFromHex(genesisBlockHashHex)
    await #expect(throws: BlockSourceError.self) {
        _ = try await source.block(for: hashInternal)
    }
}

@Test func notFoundMapsTo404() async {
    let client = MockHTTPClient()
    client.enqueue(.notFound())

    let source = makeSource(client: client)
    do {
        _ = try await source.blockHash(atHeight: 999_999_999)
        Issue.record("expected throw")
    } catch let error as BlockSourceError {
        if case .notFound = error { /* ok */ } else {
            Issue.record("expected .notFound, got \(error)")
        }
    } catch {
        Issue.record("expected BlockSourceError, got \(error)")
    }
}

// MARK: - Retry / backoff

@Test func retriesOn500WithExponentialBackoff() async throws {
    let client = MockHTTPClient()
    client.enqueue(.serverError())       // attempt 1 → 500
    client.enqueue(.serverError())       // attempt 2 → 500
    client.enqueue(.ok(body: "42"))      // attempt 3 → 200
    client.enqueue(.ok(body: sampleBlockHashDisplayHex))

    let source = makeSource(client: client)
    let tip = try await source.bestTip()

    #expect(tip.height == 42)
    // Three hits to /blocks/tip/height (2 failed + 1 success), then 1 for /hash = 4 total.
    #expect(client.records.count == 4)
    let heightHits = client.records.filter { $0.url.path.hasSuffix("/blocks/tip/height") }
    #expect(heightHits.count == 3)
}

@Test func honorsRetryAfterOn429() async throws {
    let client = MockHTTPClient()
    client.enqueue(.rateLimited(retryAfterSeconds: 1))
    client.enqueue(.ok(body: sampleBlockHashDisplayHex))

    let source = makeSource(client: client, baseRetryDelay: .milliseconds(10))

    let start = ContinuousClock.now
    _ = try await source.blockHash(atHeight: 1)
    let elapsed = ContinuousClock.now - start

    // Lower bound: Retry-After (1s) was honored, not base delay (10ms).
    // Upper bound: regression-tripwire only — Task.sleep precision under
    // CI load is unbounded, so we allow generous slack rather than
    // asserting precisely on wall-clock.
    #expect(elapsed >= .milliseconds(900))
    #expect(elapsed < .seconds(5))
    #expect(client.records.count == 2)
}

@Test func givesUpAfterMaxRetries() async {
    let client = MockHTTPClient()
    // maximumRetries=2 → at most 3 total attempts before giving up.
    for _ in 0..<10 { client.enqueue(.serverError()) }

    let source = makeSource(client: client, maximumRetries: 2, baseRetryDelay: .milliseconds(1))
    await #expect(throws: BlockSourceError.self) {
        _ = try await source.blockHash(atHeight: 1)
    }
    #expect(client.records.count == 3)
}

// MARK: - Pacing

@Test func requestsArePacedByMinimumDelay() async throws {
    let client = MockHTTPClient()
    for _ in 0..<5 {
        client.enqueue(.ok(body: sampleBlockHashDisplayHex))
    }

    let delay = Duration.milliseconds(50)
    let source = makeSource(client: client, minimumInterRequestDelay: delay)

    let start = ContinuousClock.now
    for height in 0..<5 {
        _ = try await source.blockHash(atHeight: height)
    }
    let elapsed = ContinuousClock.now - start

    // 5 requests → 4 inter-request gaps → total ≥ 4 × minimumDelay.
    // Allow generous headroom; assert only the lower bound.
    #expect(elapsed >= delay * 4)
}

@Test func concurrentRequestsSerializeThroughPacer() async throws {
    let client = MockHTTPClient()
    let count = 10
    for _ in 0..<count {
        client.enqueue(.ok(body: sampleBlockHashDisplayHex))
    }

    let delay = Duration.milliseconds(50)
    let source = makeSource(client: client, minimumInterRequestDelay: delay)

    let testStart = ContinuousClock.now
    try await withThrowingTaskGroup(of: Void.self) { group in
        for height in 0..<count {
            group.addTask { _ = try await source.blockHash(atHeight: height) }
        }
        try await group.waitForAll()
    }
    let testElapsed = ContinuousClock.now - testStart

    // Pacer reserves `count` slots spaced `delay` apart. The last slot is
    // at `(count-1) * delay` after the first, and no task's HTTP start can
    // precede its reserved slot (Task.sleep(until:) wakes at-or-after the
    // deadline). So total elapsed from `testStart` to all tasks completing
    // must be ≥ (count-1) * delay.
    //
    // Pairwise gaps in the recorded request-start timestamps CAN be less
    // than `delay` due to wake-up jitter asymmetry between tasks (task N
    // may be slow to schedule while task N+1 is quick). Whole-test elapsed
    // is the robust lower-bound check.
    let expectedMinimum = delay * (count - 1)
    #expect(testElapsed >= expectedMinimum,
            "10 concurrent requests finished in \(testElapsed); expected ≥ \(expectedMinimum)")
    #expect(client.records.count == count)
}
