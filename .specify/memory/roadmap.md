# swift-bitcoin Product Roadmap

**Version**: v1.0.0  
**Last Updated**: 2025-12-05  
**Status**: Active Development

---

## Vision & Goals

**Vision**: Provide a Swift-native interface to Bitcoin Core, enabling developers to embed a full Bitcoin node in Swift applications with idiomatic APIs for node lifecycle management and RPC access.

**Goals**:
1. **Embedded Node**: Run Bitcoin Core in-process via C++ interoperability
2. **Swift-Native API**: Expose Bitcoin Core functionality through idiomatic Swift APIs
3. **Cross-Platform**: Support all Tier 1 platforms (macOS, iOS, tvOS, visionOS, Linux)
4. **Modular**: Separate core node functionality from wallet support
5. **Developer Experience**: Type-safe RPC client with async/await and comprehensive documentation

**Target Audience**:
- Developers building Bitcoin wallets/applications
- Researchers exploring Bitcoin internals via Swift
- Production services requiring Bitcoin RPC in Swift environments

---

## Phases Overview

| Phase | Name | Status | File |
|-------|------|--------|------|
| 1 | Foundation | 🔜 Planned | [phase-1-foundation.md](roadmap/phase-1-foundation.md) |
| 2 | Daemon API | 🔜 Planned | [phase-2-daemon-api.md](roadmap/phase-2-daemon-api.md) |
| 3 | RPC Client | 🔜 Planned | [phase-3-rpc-client.md](roadmap/phase-3-rpc-client.md) |
| 4 | Wallet Support | 🔜 Planned | [phase-4-wallet-support.md](roadmap/phase-4-wallet-support.md) |
| 5 | Network Client | 🔜 Planned | [phase-5-network-client.md](roadmap/phase-5-network-client.md) |

**Timeline Model**: Milestone-driven (phases complete when deliverables are done)

---

## Product-Level Metrics & Success Criteria

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Build Success** | 100% Tier 1 platforms | CI green on macOS, iOS, tvOS, visionOS, Linux |
| **Test Coverage** | ≥80% public API | Swift coverage tools |
| **RPC Coverage** | Core methods typed | # typed methods / target methods |
| **Documentation Coverage** | 100% public types | DocC coverage report |
| **Sync Time (regtest)** | Baseline established | Time to complete IBD on regtest |
| **RPC Latency** | p50 < 10ms (direct) | Benchmark suite |
| **Binary Size** | Baseline tracked | Framework size per platform |
| **Example Apps** | ≥3 working examples | Node setup, RPC queries, transaction building |

---

## Global Dependencies & Sequencing

```
Phase 1 (Foundation)
    └── Phase 2 (Daemon API)
            └── Phase 3 (RPC Client)
                    ├── Phase 4 (Wallet Support)
                    └── Phase 5 (Network Client)
```

- **Phase 1 → 2**: Subtree migration and project structure must be complete before Daemon work
- **Phase 2 → 3**: Daemon lifecycle required for DirectClient to function
- **Phase 3 → 4/5**: BitcoinClient protocol must be stable; wallet and network implementations can proceed in parallel

---

## Global Risks & Assumptions

| Risk | Mitigation |
|------|------------|
| Bitcoin Core upstream breaking changes | Pin to specific release; test before upgrading |
| C++ interop complexity | Isolate unsafe code; comprehensive boundary testing |
| Platform-specific build issues | CI on all Tier 1 platforms from Phase 1 |
| BerkeleyDB licensing/availability | Defer to Phase 4; evaluate alternatives if needed |

**Assumptions**:
- Swift 6.0+ is acceptable minimum version
- Bitcoin Core v26.x is the initial target upstream version
- Direct (in-process) RPC is sufficient for initial use cases

---

## Change Log

| Version | Date | Change Type | Description |
|---------|------|-------------|-------------|
| v1.0.0 | 2025-12-05 | Initial | Created roadmap with 5 phases: Foundation, Daemon API, RPC Client, Wallet Support, Network Client |
