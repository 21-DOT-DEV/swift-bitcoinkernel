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

// All tests below this line use `HTTPStub`, which relies on
// `URLProtocol.registerClass` to intercept HTTP traffic. That mechanism
// works on Apple's URLSession but is a no-op on Linux's
// FoundationNetworking — registered protocols are not consulted, so
// requests escape to the real network and fail with DNS errors against
// the synthetic `.test` hostnames. See `roadmap.md` "Linux Test Coverage".
#if !os(Linux)

// MARK: - Helpers

/// Tip of Signet near height 210k, hex form as Esplora serves it (display order).
private let sampleBlockHashDisplayHex =
    "00000000000000000001a3bb48a04df6dd6e48ea74d30ba59be6b6c9a4e85d5e"

/// Build a source wired to an `HTTPStub`, using short delays so retry/backoff
/// and pacing tests complete quickly without sacrificing coverage.
private func makeSource(
    stub: HTTPStub,
    minimumInterRequestDelay: Duration = .milliseconds(50),
    maximumRetries: Int = 5,
    baseRetryDelay: Duration = .milliseconds(10)
) -> EsploraBlockSource {
    EsploraBlockSource(
        endpoint: stub.baseURL,
        urlSession: stub.makeSession(),
        minimumInterRequestDelay: minimumInterRequestDelay,
        maximumRetries: maximumRetries,
        baseRetryDelay: baseRetryDelay
    )
}

// MARK: - Parsing / happy path

@Test func bestTipParsesHeightFromTextResponse() async throws {
    let stub = HTTPStub()
    stub.enqueue(.ok(body: "800000"))
    stub.enqueue(.ok(body: sampleBlockHashDisplayHex))

    let source = makeSource(stub: stub)
    let tip = try await source.bestTip()

    #expect(tip.height == 800_000)
    #expect(tip.hash.count == 32)
    // Hash is stored in internal (kernel) order — reversed from display hex.
    let displayBytes = dataFromHex(sampleBlockHashDisplayHex)
    #expect(tip.hash == Data(displayBytes.reversed()))
    #expect(tip.timestamp == nil)
    // Exactly two requests: height, then hash.
    #expect(stub.records.count == 2)
    #expect(stub.records[0].url.path.hasSuffix("/blocks/tip/height"))
    #expect(stub.records[1].url.path.hasSuffix("/blocks/tip/hash"))
}

@Test func blockHashAtHeightParsesHex() async throws {
    let stub = HTTPStub()
    stub.enqueue(.ok(body: sampleBlockHashDisplayHex))

    let source = makeSource(stub: stub)
    let hash = try await source.blockHash(atHeight: 123_456)

    #expect(hash.count == 32)
    let displayBytes = dataFromHex(sampleBlockHashDisplayHex)
    #expect(hash == Data(displayBytes.reversed()))
    #expect(stub.records.first?.url.path.hasSuffix("/block-height/123456") == true)
}

@Test func blockHeaderParsesHexBytes() async throws {
    let stub = HTTPStub()
    // Esplora returns the 80-byte header as 160 hex chars (ASCII text body).
    stub.enqueue(.ok(body: genesisHeaderHex))

    let source = makeSource(stub: stub)
    let hashInternal = dataFromHex(genesisBlockHashHex)
    let header = try await source.blockHeader(for: hashInternal)

    #expect(header.version == 1)
    #expect(header.timestamp == 1231006505)
    #expect(header.bits == 0x1d00ffff)
    #expect(header.nonce == 2083236893)
    // URL path must embed the display-order hex (reversed from internal).
    let displayHex = Data(hashInternal.reversed()).map { String(format: "%02x", $0) }.joined()
    #expect(stub.records.first?.url.path.hasSuffix("/block/\(displayHex)/header") == true)
}

@Test func blockParsesRawBinary() async throws {
    let stub = HTTPStub()
    stub.enqueue(.ok(data: dataFromHex(genesisBlockHex)))

    let source = makeSource(stub: stub)
    let hashInternal = dataFromHex(genesisBlockHashHex)
    let block = try await source.block(for: hashInternal)

    #expect(block.transactionCount == 1)
    let displayHex = Data(hashInternal.reversed()).map { String(format: "%02x", $0) }.joined()
    #expect(stub.records.first?.url.path.hasSuffix("/block/\(displayHex)/raw") == true)
}

// MARK: - Error mapping

@Test func bestTipFailsOnNonNumericHeight() async {
    let stub = HTTPStub()
    stub.enqueue(.ok(body: "not-a-number"))

    let source = makeSource(stub: stub)
    await #expect(throws: BlockSourceError.self) {
        _ = try await source.bestTip()
    }
}

@Test func blockFailsOnCorruptedBody() async {
    let stub = HTTPStub()
    // Random 100 bytes — not a valid consensus-encoded block.
    stub.enqueue(.ok(data: Data((0..<100).map { UInt8($0 & 0xFF) })))

    let source = makeSource(stub: stub)
    let hashInternal = dataFromHex(genesisBlockHashHex)
    await #expect(throws: BlockSourceError.self) {
        _ = try await source.block(for: hashInternal)
    }
}

@Test func notFoundMapsTo404() async {
    let stub = HTTPStub()
    stub.enqueue(.notFound())

    let source = makeSource(stub: stub)
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
    let stub = HTTPStub()
    stub.enqueue(.serverError())       // attempt 1 → 500
    stub.enqueue(.serverError())       // attempt 2 → 500
    stub.enqueue(.ok(body: "42"))      // attempt 3 → 200
    stub.enqueue(.ok(body: sampleBlockHashDisplayHex))

    let source = makeSource(stub: stub)
    let tip = try await source.bestTip()

    #expect(tip.height == 42)
    // Three hits to /blocks/tip/height (2 failed + 1 success), then 1 for /hash = 4 total.
    #expect(stub.records.count == 4)
    let heightHits = stub.records.filter { $0.url.path.hasSuffix("/blocks/tip/height") }
    #expect(heightHits.count == 3)
}

@Test func honorsRetryAfterOn429() async throws {
    let stub = HTTPStub()
    stub.enqueue(.rateLimited(retryAfterSeconds: 1))
    stub.enqueue(.ok(body: sampleBlockHashDisplayHex))

    let source = makeSource(stub: stub, baseRetryDelay: .milliseconds(10))

    let start = ContinuousClock.now
    _ = try await source.blockHash(atHeight: 1)
    let elapsed = ContinuousClock.now - start

    // Lower bound: Retry-After (1s) was honored, not base delay (10ms).
    // Upper bound: regression-tripwire only — Task.sleep precision under
    // CI load is unbounded, so we allow generous slack rather than
    // asserting precisely on wall-clock.
    #expect(elapsed >= .milliseconds(900))
    #expect(elapsed < .seconds(5))
    #expect(stub.records.count == 2)
}

@Test func givesUpAfterMaxRetries() async {
    let stub = HTTPStub()
    // maximumRetries=2 → at most 3 total attempts before giving up.
    for _ in 0..<10 { stub.enqueue(.serverError()) }

    let source = makeSource(stub: stub, maximumRetries: 2, baseRetryDelay: .milliseconds(1))
    await #expect(throws: BlockSourceError.self) {
        _ = try await source.blockHash(atHeight: 1)
    }
    #expect(stub.records.count == 3)
}

// MARK: - Pacing

@Test func requestsArePacedByMinimumDelay() async throws {
    let stub = HTTPStub()
    for _ in 0..<5 {
        stub.enqueue(.ok(body: sampleBlockHashDisplayHex))
    }

    let delay = Duration.milliseconds(50)
    let source = makeSource(stub: stub, minimumInterRequestDelay: delay)

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
    let stub = HTTPStub()
    let count = 10
    for _ in 0..<count {
        stub.enqueue(.ok(body: sampleBlockHashDisplayHex))
    }

    let delay = Duration.milliseconds(50)
    let source = makeSource(stub: stub, minimumInterRequestDelay: delay)

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
    #expect(stub.records.count == count)
}

#endif // !os(Linux)
