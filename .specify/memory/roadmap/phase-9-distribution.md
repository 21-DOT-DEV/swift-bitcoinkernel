# Phase 9: Distribution & Release Artifacts

**Goal**: Ship `BitcoinKernel` (and `Bitcoin` where applicable) as pre-built artifacts for non-SPM consumers — XCFramework and CocoaPods — with continuity through the CocoaPods trunk freeze  
**Status**: PLANNED  
**Last Updated**: 2026-08-01  
**Funding**: Inside the 2026 funding window — Q8 (months 22–24) of the shared 2026 roadmap; the CocoaPods work is calendar-bound by the trunk freeze on 2026-12-02

---

## Key Features

### 9.1 XCFramework Artifacts

**Purpose & User Value**: Pre-built `BitcoinKernel` XCFramework for consumers outside Swift Package Manager (React Native, Flutter, Xcode-native apps).

**Success Metrics**:
- XCFramework build for `BitcoinKernel` (macOS + iOS slices) reproducible in CI
- Published as a release artifact with the tagged version
- Consumption documented (drag-in + module import)

**Dependencies**: Phase 3 (stable `BitcoinKernel` API surface — complete)

### 9.2 CocoaPods Continuity (calendar-bound)

**Purpose & User Value**: CocoaPods trunk goes permanently read-only on **2026-12-02**. Publish final trunk podspecs beforehand, then stand up a self-hosted specs repo with a documented consumption path so React Native / Flutter consumers keep a working install path.

**Success Metrics**:
- Final trunk podspec published before the freeze
- Self-hosted specs repo live with a working `source` line documented
- Install verified from the specs repo on a clean consumer project

**Dependencies**: 9.1 (the pod wraps the XCFramework artifact)

### 9.3 P2P Demo App (with refreshed example apps)

**Purpose & User Value**: The Phase 4.6 P2P demo ships as a release example; the existing NodeApp/KernelApp demos are refreshed against the current API.

**Success Metrics**:
- P2P demo builds and syncs on signet
- NodeApp/KernelApp build at the tagged version in CI

**Dependencies**: Phase 4.6 (P2P demo); Phase 5.5 optional (CBF demo)

---

## Sequencing

1. XCFramework build + CI job (can start now — Phase 3 API is complete)
2. CocoaPods trunk podspec + specs repo — **before 2026-12-02**, regardless of grant timing
3. P2P demo app after Phase 4.6; example-app refresh at release time

---

## Phase-Level Metrics

| Metric | Target |
|--------|--------|
| XCFramework CI reproducibility | Byte-stable per tag |
| Trunk podspec published | Before 2026-12-02 |
| Specs-repo install | Clean-consumer install passes |

---

## Risks & Assumptions

| Risk | Mitigation |
|------|------------|
| CocoaPods freeze lands mid-program regardless of grant timing | 9.2 is calendar-bound; schedule ahead of the date, not the quarters |
| C++ interop through XCFramework module stability | Pin the toolchain per artifact; document the Swift version requirement |
