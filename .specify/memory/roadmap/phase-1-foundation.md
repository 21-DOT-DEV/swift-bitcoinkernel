# Phase 1: Foundation

**Goal**: Migrate from git submodules to `swift-plugin-subtree`, fix the `MAIN_FUNCTION` workaround, restructure the project for dual library targets, and establish CI.

**Status**: COMPLETE  
**Last Updated**: 2026-05-07

---

## Goal

Establish the build infrastructure and project structure that all subsequent phases depend on: subtree-based upstream tracking, deterministic C++ builds, dual library targets, and cross-platform CI.

---

## Key Features

### 1.1 Subtree Migration

**Purpose & User Value**: Replace git submodules with `swift-plugin-subtree` for better upstream tracking, cleaner extraction, and reproducible builds.

**Success Metrics**:
- `subtree.yaml` created with pinned Bitcoin Core commit/tag
- Multiple extraction rules for: bitcoind, libbitcoinkernel, secp256k1, leveldb, minisketch, crc32c
- `Submodules/` directory removed
- `.gitmodules` removed
- Build succeeds on all Tier 1 platforms

**Dependencies**: None (first feature)

**Status**: COMPLETE (commit `07f17498d9d`)

---

### 1.2 MAIN_FUNCTION Header Fix

**Purpose & User Value**: Replace the lefthook `sed` workaround with a proper C++ header define, eliminating the post-checkout hook and making builds deterministic.

**Success Metrics**:
- `Sources/bitcoind/include/swift-bitcoin-config.h` created
- `MAIN_FUNCTION` defined as `int entry(int argc, char* argv[])`
- `Package.swift` updated with `-include swift-bitcoin-config.h` flag
- `lefthook.yml` post-checkout hook removed
- Build succeeds without manual intervention

**Dependencies**: 1.1 Subtree Migration

**Status**: COMPLETE

---

### 1.3 Dual Library Targets

**Purpose & User Value**: Split the package into `Bitcoin` (embedded daemon + RPC) and `BitcoinKernel` (consensus validation only) so consumers can choose minimal or full functionality.

**Success Metrics**:
- `Package.swift` exposes two library products:
  - `.library(name: "Bitcoin", targets: ["Bitcoin"])`
  - `.library(name: "BitcoinKernel", targets: ["BitcoinKernel"])`
- `Bitcoin` target wraps `bitcoind` + `RPCModels`
- `BitcoinKernel` target wraps `libbitcoinkernel` only
- Wallet functionality gated behind `wallet` package trait
- Both targets build on all Tier 1 platforms

**Dependencies**: 1.1 Subtree Migration, 1.2 MAIN_FUNCTION Fix

**Status**: COMPLETE

---

### 1.4 CI Pipeline Setup

**Purpose & User Value**: Establish CI that validates builds across all Tier 1 platforms, ensuring cross-platform reliability.

**Success Metrics**:
- GitHub Actions workflow for Tier 1 platforms: macOS (arm64, x86_64), iOS (arm64)
- SwiftLint and SwiftFormat checks pass
- Unit tests run on each platform
- Build artifacts cached for faster CI

**Dependencies**: 1.3 Dual Library Targets

**Status**: COMPLETE

---

## Phase Dependencies & Sequencing

```
1.1 Subtree Migration ✅
    └── 1.2 MAIN_FUNCTION Fix ✅
            └── 1.3 Dual Library Targets ✅
                    └── 1.4 CI Pipeline Setup ✅
```

---

## Phase-Level Metrics

| Metric | Target | Result |
|--------|--------|--------|
| Build success | All Tier 1 platforms green | ✅ |
| Test coverage | Existing tests pass | ✅ |
| Documentation | README updated with new structure | ✅ |
| Binary size | Baseline established for both targets | ✅ |

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Subtree extraction breaks build | Test extraction rules incrementally |
| BerkeleyDB unavailable on some platforms | Gated behind `wallet` trait; SQLite as default wallet backend |

---

## Phase Notes / Change Log

- 2026-05-07: Marked COMPLETE. All deliverables delivered. Subtree migration (commit `07f17498d9d`), dual targets in `Package.swift`, CI operational.
- 2025-12-05: Initial creation.