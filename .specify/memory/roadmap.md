# swift-bitcoin Product Roadmap

**Version**: v2.2.3  
**Last Updated**: 2026-05-07  
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
| **Build Success** | 100% Tier 1+2 platforms | CI green on macOS, iOS, visionOS |
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

### tvOS BitcoinKernel Support

**Status**: Planned — BitcoinKernel compiles for tvOS (libbitcoinkernel target succeeds), but full bitcoind is blocked by `fork`/`execvp` which Apple marks unavailable on tvOS. Requires conditional compilation guards in vendored C++ sources (`subprocess.h`, `exec.cpp`) to exclude daemon-only features from tvOS builds. watchOS is blocked for both targets (same primitives unavailable).

- **BitcoinKernel path**: Add `#if !TARGET_OS_TV` guards (requires `#include <TargetConditionals.h>`) around `fork`/`execvp` usage in `Sources/libbitcoinkernel/src/util/subprocess.h`. The subprocess facility is only needed for external signer support, not core consensus validation.
- **bitcoind path**: Not feasible — daemonization (`fork_daemon`), system command execution, and interactive stdin all require unavailable POSIX primitives.
- **CI**: Add tvOS build job for BitcoinKernel-only scheme once source guards are in place.
- **Dependencies**: None — independent of all roadmap phases.

### Great Consensus Cleanup

A potential soft fork (discussed on delvingbitcoin.org) that would fix the timewarp vulnerability, invalidate 64-byte transactions, and constrain legacy script usage. If activated, `libbitcoinkernel` would need to enforce new consensus rules.

- **Status**: Proposal only. No activation timeline.
- **Impact**: BitcoinKernel inherits consensus changes from upstream `libbitcoinkernel` — no Swift changes needed unless the kernel API surface changes.

---

## Change Log

| Version | Date | Change Type | Description |
|---------|------|-------------|-------------|
| v2.2.3 | 2026-05-07 | PATCH | Added Filter Registration API (7.2) to Phase 7. Based on cross-implementation research across LDK, CLN, BDK, Kyoto, and Floresta. LDK's `Filter` trait pattern selected as best approach. |: change logs now describe features by BIP number, project names kept only in Reference lines as implementation pointers. Global risks use BIP numbers. Mirrors v2.2.1 Floresta/Utreexo treatment. |
| v2.2.1 | 2026-05-07 | PATCH | Added Utreexo as a Future Consideration in index and Phase 6 note. Clarified that Floresta references are for P2P infrastructure (wire protocol, BIP 324, mempool), not Utreexo itself. |
| v2.2.0 | 2026-05-07 | MINOR | Added Phase 8: RPC Server & Privacy (JSON-RPC server, Ricochet, STONEWALL, PayJoin/BIP 78, BIP 47 Payment Codes). Added Binary Fuse filter alternative note to Phase 5. Added Cluster Mempool alignment and node fingerprinting privacy notes to Phase 6. Cross-referenced delvingbitcoin.org (Binary Fuse filters, Great Consensus Cleanup Revival, Cluster Mempool, Fingerprinting nodes). Explored kernel-i-node, kernel-node, rust-esplora-client, yuki, MainFltrWallet, samourai-wallet-android. |
| v2.1.0 | 2026-05-07 | MINOR | Added Phase 7: Lightning Integration. Based on thorough analysis of Core Lightning (CLN) `lightningd/bitcoind.c` and `plugins/bcli.c`. CLN uses a plugin-based Bitcoin backend with 5 required methods. Key finding: CLN does NOT use ZMQ (timer-based polling only). The one BitcoinKernel API gap is UTXO lookup (`gettxout`). |
| v2.0.0 | 2026-05-07 | MAJOR | Complete restructure: Phases 1-3 marked COMPLETE (was PLANNED). Old Phase 4 (Wallet) absorbed into Phase 3. Old Phase 5 (Network Client) replaced by new Phase 4 (P2P Networking), Phase 5 (Compact Block Filters), Phase 6 (Advanced P2P). Added BIP coverage: 130, 133, 152, 155, 157, 158, 324, 339. Cross-referenced Kyoto, Floresta, LDK-Node, fltr ecosystem, SwiftSync, hintsfile, libutreexo. Verified Lightning compatibility. |
| v1.0.0 | 2025-12-05 | Initial | Created roadmap with 5 phases: Foundation, Daemon API, RPC Client, Wallet Support, Network Client |