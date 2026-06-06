# swift-bitcoinkernel Product Roadmap

**Version**: v2.2.4  
**Last Updated**: 2026-06-04  
**Status**: Active Development

---

## Vision & Goals

**Vision**: Provide a Swift-native interface to Bitcoin Core, enabling developers to embed a full Bitcoin node (`Bitcoin` target) or integrate consensus validation (`BitcoinKernel` target) in Swift applications with idiomatic, async/await APIs.

**Goals**:
1. **Embedded Daemon**: Run Bitcoin Core in-process via Swift/C++ interoperability (`Bitcoin` target)
2. **Kernel-as-Node-Layer**: Expose `libbitcoinkernel` consensus validation as a reusable node layer that any wallet SDK can consume (`BitcoinKernel` target)
3. **Swift-Native P2P**: Deliver blocks and broadcast transactions directly from Swift peers — no Rust FFI, no external runtime dependencies
4. **Compact Filter Light Client**: Implement BIP 157/158 compact block filters in Swift for privacy-preserving wallet sync
5. **Cross-Platform**: Support macOS 15+ and iOS 18+ (Tier 1); Linux, visionOS (Tier 2); tvOS BitcoinKernel-only (planned)
6. **Developer Experience**: Type-safe RPC client, async/await throughout, comprehensive DocC documentation

**Target Audience**:
- Wallet developers needing a Swift-native node layer (`BitcoinKernel`)
- Application developers embedding a full Bitcoin node (`Bitcoin`)
- Lightning implementers requiring block delivery, tx broadcast, and fee estimation
- Researchers exploring Bitcoin internals via Swift

---

## Phases Overview

| Phase | Name / Goal | Status | File Path |
|-------|-------------|--------|-----------|
| 1 | Foundation | COMPLETE | [phase-1-foundation.md](roadmap/phase-1-foundation.md) |
| 2 | Daemon API | COMPLETE | [phase-2-daemon-api.md](roadmap/phase-2-daemon-api.md) |
| 3 | RPC Client + Wallet RPC | COMPLETE | [phase-3-rpc-client.md](roadmap/phase-3-rpc-client.md) |
| 4 | P2P Networking | NEXT UP | [phase-4-p2p-networking.md](roadmap/phase-4-p2p-networking.md) |
| 5 | Compact Block Filters | PLANNED | [phase-5-compact-filters.md](roadmap/phase-5-compact-filters.md) |
| 6 | Advanced P2P | FUTURE | [phase-6-advanced-p2p.md](roadmap/phase-6-advanced-p2p.md) |
| 7 | Lightning Integration | FUTURE | [phase-7-lightning-integration.md](roadmap/phase-7-lightning-integration.md) |
| 8 | RPC Server & Privacy | FUTURE | [phase-8-rpc-server.md](roadmap/phase-8-rpc-server.md) |

**Timeline Model**: Milestone-driven (phases complete when deliverables are done).

> **Historical note**: The original v1.0.0 roadmap (2025-12-05) defined 5 forward-looking phases. Phases 1-3 are now complete. Old Phase 4 (Wallet Support) was absorbed into Phase 3 — wallet is RPC-only, `BitcoinKernel` is a node layer, not a wallet. Old Phase 5 (Network Client) was replaced by the new P2P phases (4-6).

---

## Product-Level Metrics & Success Criteria

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Build Success** | 100% Tier 1+2 platforms | CI green on macOS, iOS, visionOS, Linux |
| **Test Coverage** | ≥80% public API | Swift coverage tools |
| **RPC Coverage** | 171 typed methods (done) | All Bitcoin Core v31.x RPCs covered |
| **Documentation Coverage** | 100% public types | DocC coverage report |
| **P2P Block Throughput** | Baseline established | Blocks/sec on signet via P2P BlockSource |
| **P2P Tx Broadcast Latency** | Baseline established | Time from send to first peer relay |
| **CBF Sync Time (signet)** | Baseline established | Time to full signet sync via compact filters |
| **Example Apps** | ≥3 working examples | NodeApp (daemon), KernelApp (kernel), P2P demo (future) |

---

## High-Level Dependencies & Sequencing

```
Phase 1 (Foundation) ✅
    └── Phase 2 (Daemon API) ✅
            └── Phase 3 (RPC Client + Wallet RPC) ✅
                    └── Phase 4 (P2P Networking) 🔜
                            ├── P2P BlockSource → BlockchainSync
                            ├── Tx broadcast
                            └── BIP 324 v2 transport
                                    └── Phase 5 (Compact Block Filters) 📋
                                            ├── BIP 157/158 filter impl
                                            └── CBF-based BlockSource
                                                    └── Phase 6 (Advanced P2P) 🔮
                                                            ├── Mempool sync (cluster-aligned)
                                                            └── Addr gossip (fingerprinting-safe)
                                                                    └── Phase 7 (Lightning Integration) 🔮
                                                                            ├── UTXO lookup API
                                                                            ├── Filter registration API
                                                                            ├── CLN Bitcoin backend plugin
                                                                            └── Lightning fee estimation
                                                                                    └── Phase 8 (RPC Server & Privacy) 🔮
                                                                                            ├── JSON-RPC server
                                                                                            ├── Ricochet / STONEWALL
                                                                                            └── BIP 47 / BIP 78
```

- **Phase 3 → 4**: `BlockSource` protocol and `BlockchainSync` engine must be stable before P2P BlockSource implementation
- **Phase 4 → 5**: P2P wire protocol (message framing, handshake, header sync) must exist before compact filter messages (`getcfheaders`, `getcfilters`) can be layered on top
- **Phase 5 → 6**: Compact filter infrastructure enables efficient mempool-aware peer selection and addr gossip
- **Phase 6 → 7**: Mempool sync (Phase 6) provides the fee data needed for Lightning-aware fee estimation; UTXO lookup API (7.1) can be developed independently once Phase 3 is done
- **Phase 7 → 8**: CLN plugin and UTXO lookup provide the foundation for a general-purpose RPC server; privacy features are independent of Lightning
- **Phase 4 and 5 are sequential** — CBF messages extend the P2P wire protocol established in Phase 4

---

## Global Risks & Assumptions

| Risk | Mitigation |
|------|------------|
| Bitcoin Core upstream breaking changes | Pin to specific release via `subtree.yaml`; test before upgrading |
| C++ interop complexity | Isolate unsafe code; comprehensive boundary testing; Swift 6 strict concurrency |
| P2P wire protocol complexity (100+ message types) | Phase delivery: basic messages first (BIP 324, BIP 130, BIP 133, BIP 339), advanced later; reference Kyoto/Floresta/SwiftSync for wire protocol patterns |
| BIP 324 (v2 transport) implementation difficulty | Leverage `swift-event` (libevent) for async I/O; reference Floresta's BIP 324 implementation for protocol logic |
| Platform-specific P2P limitations (iOS background sockets) | Document limitations; focus macOS first, iOS with BGTaskScheduler |
| Compact filter false-positive rate | Tune Golomb-Rice parameters per BIP 158 spec; validate against Bitcoin Core test vectors |

**Assumptions**:
- Swift 6.3+ (swift-tools-version 6.3) is the minimum toolchain
- Bitcoin Core v31.x is the current pinned upstream version (via `subtree.yaml`)
- `swift-event` (libevent) provides sufficient async I/O primitives for P2P networking
- `BitcoinKernel` is a node layer consumed by wallets/SDKs, not a wallet itself
- No Rust FFI — all new features are Swift-native, referencing Rust implementations (Kyoto, Floresta, SwiftSync) for protocol logic only
- Signet is the recommended real-network target for testing; mainnet IBD is documented as impractical for mobile

---

## Future Considerations

These are not committed phases — they're areas to monitor and potentially incorporate if/when the ecosystem matures.

### Utreexo — Stateless Validation

[Utreexo](https://github.com/mit-dci/libutreexo) is a cryptographic UTXO accumulator that enables stateless block validation: nodes don't store the full UTXO set (~10 GB chainstate), only accumulator roots. Blocks include proofs of UTXO membership. This could dramatically reduce BitcoinKernel's storage requirements.

- **Status**: Research/production (Floresta uses Utreexo via `rustreexo`). No BIP, no Bitcoin Core integration.
- **Swift-native path**: Would require a Swift implementation of the Utreexo accumulator (reference `libutreexo` C99 code and `rustreexo` Rust crate).
- **Integration challenge**: Requires changes to how `libbitcoinkernel` resolves UTXOs — replacing `CCoinsViewDB` with accumulator proofs.
- **Monitor**: Floresta's Utreexo adoption, any Bitcoin Core Utreexo integration proposals.

### Direct-to-Peer Transaction Broadcast (Libre-Relay)

Re-creates the capability of [`tx-pigeon`](https://github.com/stutxo/tx-pigeon) (Rust) as a Swift-native feature. It broadcasts a transaction by connecting directly to peers that advertise the `NODE_LIBRE_RELAY` service flag and handing them the transaction over the P2P wire, rather than relaying through a local node's mempool. The use case is delivering transactions a default-policy node would not relay (out-of-policy or censorship-resistant broadcast).

- **Status**: Future Consideration. No Rust FFI; `tx-pigeon` is a protocol-logic reference only, consistent with the Kyoto/Floresta/SwiftSync convention used elsewhere in this roadmap.
- **Relationship to committed phases**: the mechanism is largely already scheduled. Generic `inv`/`getdata`/`tx` broadcast is Phase 4.5, DNS-seed bootstrap and peer management are Phase 4.3, `addr`/`addrv2` discovery is Phase 6.2, and Tor SOCKS5 routing is Phase 4.6 (via `swift-tor`). This is the thin opinionated layer on top, not a new subsystem.
- **Net-new surface**: filter discovered peers by the `NODE_LIBRE_RELAY` service bit (bit 29), fan a transaction out to the matching peer set, and optionally keep serving it from the latest block after confirmation (`tx-pigeon`'s "garbage man" behaviour).
- **Why not a committed phase**: it depends on the full Phase 4 P2P stack existing first, and out-of-policy relay is a niche use case relative to the core node-layer mission. Captured here without committing the project to it pre-1.0.
- **Monitor / promote**: revisit once Phase 4 ships. If there is real demand, promote to a Phase 6 sub-feature (after 6.2) with success metrics.

### tvOS BitcoinKernel Support

**Status**: Planned — BitcoinKernel compiles for tvOS (libbitcoinkernel target succeeds), but full bitcoind is blocked by `fork`/`execvp` which Apple marks unavailable on tvOS. Requires conditional compilation guards in vendored C++ sources (`subprocess.h`, `exec.cpp`) to exclude daemon-only features from tvOS builds. watchOS is blocked for both targets (same primitives unavailable).

- **BitcoinKernel path**: Add `#if !TARGET_OS_TV` guards (requires `#include <TargetConditionals.h>`) around `fork`/`execvp` usage in `Sources/libbitcoinkernel/src/util/subprocess.h`. The subprocess facility is only needed for external signer support, not core consensus validation.
- **bitcoind path**: Not feasible — daemonization (`fork_daemon`), system command execution, and interactive stdin all require unavailable POSIX primitives.
- **CI**: Add tvOS build job for BitcoinKernel-only scheme once source guards are in place.
- **Dependencies**: None — independent of all roadmap phases.

### Linux Test Coverage Gaps

**Status**: One test file (`RegtestChainBuilder`, Gap 1) is gated to Apple platforms; Gaps 2 and 3 are resolved (see below) and the rest of the suite runs on Linux CI.

**Gap 1 — `RegtestChainBuilder` (CryptoKit)**

- Files: `Tests/BitcoinKernelTests/Support/RegtestChainBuilder.swift`, `RegtestChainBuilderTests.swift`, `BlockchainSyncEngineTests.swift` — guarded by `#if canImport(CryptoKit)`.
- Cause: The synthetic block miner uses `CryptoKit.SHA256` for `sha256d`. CryptoKit is Apple-only.
- Recommended fix: Add an Apache-2.0 dep on [`apple/swift-crypto`](https://github.com/apple/swift-crypto) (Linux-only via `.product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))`) and `import Crypto` under `#else`. swift-crypto provides drop-in CryptoKit equivalents on Linux. Requires a constitutional amendment per `AGENTS.md` ("Ask first: add new third-party dependencies").
- Alternative: expose libbitcoinkernel's internal `CSHA256` via a new C bridge target (precedent: [`swift-secp256k1`'s `Utility.h`](https://github.com/21-DOT-DEV/swift-secp256k1/blob/main/Sources/libsecp256k1/include/Utility.h)). Avoids the dep but adds C++→C wrapper scaffolding for one test helper.
- Impact: ~12 integration tests skipped on Linux. Unit coverage of `BlockchainSync` itself remains via mocks; what's lost is end-to-end validation through `processBlock`.

**Gap 2 — `HTTPStub` (URLProtocol stubbing on Linux) — RESOLVED (2026-06-01)**

- Files: `Tests/BitcoinKernelTests/BlockSourceTests.swift` — no longer platform-gated.
- Cause: the old `HTTPStub` relied on `URLProtocol` interception. When that silently failed (a no-op on Linux's FoundationNetworking, and flaky even on Apple), stubbed requests escaped to real DNS against synthetic hostnames; because `EsploraBlockSource` treats DNS failures as retryable, it retried until the test hung.
- Fix (shipped): exactly the recommended refactor. `EsploraBlockSource` now depends on a public `HTTPDataFetching` protocol (`func data(from: URL) async throws -> (Data, URLResponse)`); `URLSession` conforms, and the public `init(endpoint:urlSession:...)` is unchanged. Tests inject `MockHTTPClient` (`Tests/BitcoinKernelTests/Support/MockHTTPClient.swift`), a per-instance in-memory double — no `URLProtocol`, no network, deterministic and identical on every platform. The old `HTTPStub` was deleted.
- Impact: the ~12 retry/pacing/Retry-After tests now run on Linux too; the most complex part of `EsploraBlockSource` regained cross-platform coverage with no third-party deps.

**Gap 3 — Process-global kernel state under single-process parallel tests — RESOLVED (2026-06-01)**

- File: `Tests/BitcoinKernelTests/LoggingTests.swift` — `loggingConnectionReceivesMessages()` is no longer platform-gated.
- Cause (corrected): the premise that Apple gives each test a fresh xctest process is false under swift-testing, which runs the whole bundle in one process (like Linux). The fault is broader than the logger — libbitcoinkernel's process-global state isn't safe under concurrent in-process lifecycles. Two symptoms: (a) the kernel's `StartLogging` (via `btck_logging_connection_create`) and the embedded `bitcoind`'s `StartLogging` both `assert(m_buffering)` on the one `LogInstance`, so running both in a process SIGABRTs (surfaced by `swift test --traits wallet`); (b) parallel `Context`/`ChainstateManager` create/destroy cycles spin/livelock on `cs_main`/chainstate.
- Fix (shipped): handled in test code, not with `--no-parallel`. Tests that create a `Context`/`ChainstateManager` or mutate the global logger carry the `.kernelSerialized` trait (`Tests/BitcoinKernelTests/Support/KernelSerialization.swift`) — a `TestScoping` trait whose shared `AsyncSemaphore` serializes them against each other across all files and suites while everything else stays parallel (`.serialized` can't, since it only orders tests within one suite). The logging-test callback is also lock-guarded. The package therefore runs as ONE parallel `swift test`; only the `Bitcoin Integration` daemon suite is split into its own invocation, because the embedded `bitcoind` holds the global logger open for its lifetime and can't share a process. (The earlier "make `LoggingConnection` a `static let shared` singleton" idea was rejected: a never-destroyed connection would make the daemon's `StartLogging` assert.)
- Impact: the Linux-gated test is re-enabled; `LoggingConnection` API coverage now runs on every platform.

### Test-Time Clock Injection (`swift-clocks`)

**Status**: Future enhancement — current timing-sensitive tests use a per-call `onWillSleep:` hook on `Daemon.poll` to capture intended sleep durations deterministically, plus widened wall-clock ceilings as regression tripwires. This works at small scale but doesn't generalize.

- **Trigger**: Adopt [Point-Free's `swift-clocks`](https://github.com/pointfreeco/swift-clocks) (`TestClock`) once we have ≥5 timing-sensitive tests where the per-call hook pattern feels repetitive, OR when Apple ships a stdlib `TestClock` (whichever comes first).
- **Apple's stance**: The Swift team has indicated they're [open to a built-in `TestClock`](https://forums.swift.org/t/controllable-clock-support-in-swift-testing/81246) but it isn't currently a priority; community is invited to draft an evolution proposal. Point-Free has stated they would retire `swift-clocks` if a built-in arrives.
- **Migration path**: Parameterize timed-sleep callsites (`Daemon.poll`, `EsploraBlockSource` retry path, `DirectTransport` timeout) on a `Clock` parameter defaulting to `ContinuousClock()`. Tests inject `TestClock` for virtual-time advancement.
- **Dependencies**: Adds one Apache-2.0 third-party dep (Point-Free `swift-clocks`) — requires explicit approval per `AGENTS.md` policy on new third-party deps.

### Great Consensus Cleanup

A potential soft fork (discussed on delvingbitcoin.org) that would fix the timewarp vulnerability, invalidate 64-byte transactions, and constrain legacy script usage. If activated, `libbitcoinkernel` would need to enforce new consensus rules.

- **Status**: Proposal only. No activation timeline.
- **Impact**: BitcoinKernel inherits consensus changes from upstream `libbitcoinkernel` — no Swift changes needed unless the kernel API surface changes.

---

## Change Log

| Version | Date | Change Type | Description |
|---------|------|-------------|-------------|
| v2.2.4 | 2026-06-04 | PATCH | Added "Direct-to-Peer Transaction Broadcast (Libre-Relay)" as a Future Consideration: a Swift-native re-creation of `tx-pigeon` (reference link), scoped as the opinionated layer over Phase 4.5 broadcast and 6.2 service-flag discovery, not a committed phase. |
| v2.2.3 | 2026-05-07 | PATCH | Added Filter Registration API (7.2) to Phase 7. Based on cross-implementation research across LDK, CLN, BDK, Kyoto, and Floresta. LDK's `Filter` trait pattern selected as best approach. |: change logs now describe features by BIP number, project names kept only in Reference lines as implementation pointers. Global risks use BIP numbers. Mirrors v2.2.1 Floresta/Utreexo treatment. |
| v2.2.1 | 2026-05-07 | PATCH | Added Utreexo as a Future Consideration in index and Phase 6 note. Clarified that Floresta references are for P2P infrastructure (wire protocol, BIP 324, mempool), not Utreexo itself. |
| v2.2.0 | 2026-05-07 | MINOR | Added Phase 8: RPC Server & Privacy (JSON-RPC server, Ricochet, STONEWALL, PayJoin/BIP 78, BIP 47 Payment Codes). Added Binary Fuse filter alternative note to Phase 5. Added Cluster Mempool alignment and node fingerprinting privacy notes to Phase 6. Cross-referenced delvingbitcoin.org (Binary Fuse filters, Great Consensus Cleanup Revival, Cluster Mempool, Fingerprinting nodes). Explored kernel-i-node, kernel-node, rust-esplora-client, yuki, MainFltrWallet, samourai-wallet-android. |
| v2.1.0 | 2026-05-07 | MINOR | Added Phase 7: Lightning Integration. Based on thorough analysis of Core Lightning (CLN) `lightningd/bitcoind.c` and `plugins/bcli.c`. CLN uses a plugin-based Bitcoin backend with 5 required methods. Key finding: CLN does NOT use ZMQ (timer-based polling only). The one BitcoinKernel API gap is UTXO lookup (`gettxout`). |
| v2.0.0 | 2026-05-07 | MAJOR | Complete restructure: Phases 1-3 marked COMPLETE (was PLANNED). Old Phase 4 (Wallet) absorbed into Phase 3. Old Phase 5 (Network Client) replaced by new Phase 4 (P2P Networking), Phase 5 (Compact Block Filters), Phase 6 (Advanced P2P). Added BIP coverage: 130, 133, 152, 155, 157, 158, 324, 339. Cross-referenced Kyoto, Floresta, LDK-Node, fltr ecosystem, SwiftSync, hintsfile, libutreexo. Verified Lightning compatibility. |
| v1.0.0 | 2025-12-05 | Initial | Created roadmap with 5 phases: Foundation, Daemon API, RPC Client, Wallet Support, Network Client |