# Phase 1: Foundation

**Goal**: Migrate from git submodules to swift-plugin-subtree, fix the MAIN_FUNCTION workaround, and restructure the project for dual library targets.

**Status**: 🔜 Planned  
**Last Updated**: 2025-12-05

---

## Features

### 1.1 Subtree Migration

**Purpose & User Value**: Replace git submodules with swift-plugin-subtree for better upstream tracking, cleaner extraction, and reproducible builds.

**Success Metrics**:
- `subtree.yaml` created with pinned Bitcoin Core commit/tag
- Multiple extraction rules for: bitcoind, secp256k1, leveldb, minisketch, crc32c
- `Submodules/` directory removed
- `.gitmodules` removed
- Build succeeds on all Tier 1 platforms

**Dependencies**: None (first feature)

**Notes**:
- All extractions from single upstream (bitcoin/bitcoin repo)
- Follow pattern from swift-secp256k1's subtree.yaml
- Pin to Bitcoin Core v26.x initially

---

### 1.2 MAIN_FUNCTION Header Fix

**Purpose & User Value**: Replace the lefthook sed workaround with a proper C++ header define, eliminating the post-checkout hook and making builds deterministic.

**Success Metrics**:
- `Sources/bitcoind/include/swift-bitcoin-config.h` created
- `MAIN_FUNCTION` defined as `int entry(int argc, char* argv[])`
- `Package.swift` updated with `-include swift-bitcoin-config.h` flag
- `lefthook.yml` post-checkout hook removed
- Build succeeds without manual intervention

**Dependencies**: 1.1 Subtree Migration (extraction must place files correctly)

**Notes**:
- Header should be self-documenting with comments explaining the purpose
- Consider future extensibility for other defines

---

### 1.3 Dual Library Targets

**Purpose & User Value**: Split the package into `Bitcoin` (core node) and `BitcoinWalletSupport` (with BerkeleyDB) so users can choose minimal or full functionality.

**Success Metrics**:
- `Package.swift` exposes two library products:
  - `.library(name: "Bitcoin", targets: ["Bitcoin"])`
  - `.library(name: "BitcoinWalletSupport", targets: ["BitcoinWalletSupport"])`
- `Bitcoin` target compiles without BerkeleyDB dependency
- `BitcoinWalletSupport` target includes BerkeleyDB via swift-berkeleydb
- Both targets build on all Tier 1 platforms
- README documents the difference between targets

**Dependencies**: 1.1 Subtree Migration, 1.2 MAIN_FUNCTION Fix

**Notes**:
- `BitcoinWalletSupport` depends on `Bitcoin` (additive)
- Wallet functionality may require Bitcoin Core build flags (e.g., `--enable-wallet`)

---

### 1.4 CI Pipeline Setup

**Purpose & User Value**: Establish CI that validates builds across all Tier 1 platforms, ensuring cross-platform reliability from day one.

**Success Metrics**:
- GitHub Actions workflow for all Tier 1 platforms:
  - macOS (arm64, x86_64)
  - iOS (arm64)
  - tvOS (arm64)
  - visionOS (arm64)
  - Linux (x86_64, arm64)
- SwiftLint and SwiftFormat checks pass
- Unit tests run on each platform
- Build artifacts cached for faster CI

**Dependencies**: 1.3 Dual Library Targets

**Notes**:
- Use matrix builds for platform coverage
- Consider Bitrise for Apple platforms, GitHub Actions for Linux

---

## Phase Dependencies & Sequencing

```
1.1 Subtree Migration
    └── 1.2 MAIN_FUNCTION Fix
            └── 1.3 Dual Library Targets
                    └── 1.4 CI Pipeline Setup
```

---

## Phase-Level Metrics

| Metric | Target |
|--------|--------|
| Build success | All Tier 1 platforms green |
| Test coverage | Existing tests pass |
| Documentation | README updated with new structure |
| Binary size | Baseline established for both targets |

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Subtree extraction breaks build | Test extraction rules incrementally |
| BerkeleyDB unavailable on some platforms | Document platform limitations in README |
| CI time too long | Parallelize platform builds, cache dependencies |
