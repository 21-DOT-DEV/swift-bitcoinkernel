<!--
Sync Impact Report (latest):
- Version: 2.0.0 → 2.1.0 (MINOR — Tuist Projects guidance expanded: demo-app CI mandate + corrected commands)
- Change Type: Amendment (Implementation Guidance → Tuist Projects Folder)
- Scope: Projects/ demo apps (NodeApp, KernelApp) now build+test on macOS and iOS via .github/workflows/tuist-apps.yml; corrected stale example commands and Purpose; added a dependency-graph-resolution requirement. Companion repo change: Projects/Project.swift swift-tor pin 0.1.0 → 0.1.1 (aligns swift-event 0.2.1 with root, unbreaking tuist generate).

Prior amendment (1.0.0 → 2.0.0, MAJOR — structural rewrite, platform scope redefinition, principle consolidation):
- Change Type: Full rewrite
- Scope: swift-bitcoinkernel package (/Users/csjones/Developer/swift-bitcoinkernel)
- Structure: Seven core principles + implementation practices + governance, three-tier enforcement (MUST/SHOULD/MAY + explicit MUST NOT)
- Core Principles (v2.0.0):
  I.   Scope & Bitcoin Core Alignment
  II.  C++ Interop & Resource Safety
  III. Node Lifecycle & Shutdown Safety
  IV.  API Design & RPC Surface
  V.   Spec-First & Test-Driven Development
  VI.  Cross-Platform CI & Quality Gates
  VII. Open Source Excellence
- Principle changes vs v1.0.0 (8 → 7 principles):
  • Merged "RPC Client Design & Reliability" + "API Design & Swift Idioms" → "API Design & RPC Surface"
  • Renamed "C++ Interoperability & Memory Safety" → "C++ Interop & Resource Safety" (broader framing)
  • Renamed "Node Lifecycle Management" → "Node Lifecycle & Shutdown Safety" (emphasizes shutdown/restart)
  • Retained Scope / Spec-First & TDD / Cross-Platform CI / Open Source Excellence (aligned with sibling canon)
- New structural elements:
  • Runtime-dependency allowlist with MAJOR-amendment gate (Principle I)
  • Tiered platform model: Tier 1 (CI-gated) vs Tier 2 (aspirational) (Principle VI)
  • Local-patches discipline codified (Principle I + Implementation Guidance)
  • Org-level CONTRIBUTING.md / SECURITY.md deferral to 21-DOT-DEV/.github (Principle VII)
  • Compliance Review Triggers table (Governance)
- Sibling cross-references:
  • swift-secp256k1 v1.0.0 → 7-principle structure, three-tier enforcement, Tuist Projects folder, Appendix pattern, BDFL governance, Pre-1.0 stability posture
  • swift-tor v1.1.0 → runtime-dependency allowlist (MAJOR-amendment gate), Compliance Review Triggers table, narrow-scope framing
  • swift-event v1.0.1 → two-layer API design, Swift 6 strict-concurrency reference, Swift API Design Guidelines citation, SemVer 2.0.0 citation
  • swift-openssl v1.0.1 → org-level deferrals to 21-DOT-DEV/.github, CI workflow enumeration pattern
- Alignment corrections vs v1.0.0:
  • Platforms: now match Package.swift (macOS 15+ / iOS 18+); Linux added per maintainer direction; tvOS/visionOS/watchOS/Windows/Android moved to Tier 2 aspirational
  • Bitcoin Core pin: v26.x planned → v31.0rc4 (current reality)
  • Products: 6-product claim → 2 library products (Bitcoin + BitcoinKernel); C/C++ vendored libs are internal targets, not products
  • Wallet: "BitcoinWalletSupport" separate library → `wallet` package trait (current reality)
  • Swift toolchain: 6.0+ → swift-tools-version 6.3, C++20
- Templates Status:
  ⚠ .specify/templates/plan-template.md — Constitution Check section is a placeholder; requires alignment with v2.0.0 principles
  ⚠ .specify/templates/spec-template.md — Generic scaffold; requires alignment review for Principle V language
  ⚠ .specify/templates/tasks-template.md — Generic scaffold; requires principle-driven task categories (C++ interop, node lifecycle, RPC)
  ⚠ .specify/templates/checklist-template.md — Generic scaffold; requires alignment review
- Follow-up TODOs:
  • Audit the 4 .specify/templates/* files against v2.0.0 principles in a follow-up pass
  • Verify C++20 Bitcoin Core actually builds on Tier 2 platforms before any tier promotion
  • Upgrade Swift 6 strict-concurrency guidance from SHOULD → MUST once verified across all targets
  • Ensure SwiftLint / SwiftFormat infrastructure lands before the linting MUST gate takes effect
-->

# Constitution for swift-bitcoinkernel

## Preamble

This constitution governs the **swift-bitcoinkernel** package, a Swift 6 wrapper around Bitcoin Core's C++ implementation providing embedded-node functionality and high-level RPC access for Apple platforms and Linux.

**Scope**: This repository only. Covers the `Bitcoin` high-level Swift library (embedded daemon bridge + typed RPC client + response models), the `BitcoinKernel` low-level library (consensus-validation bindings), and the vendored Bitcoin Core source tree under `Vendor/bitcoin/` synchronized via the `subtree` CLI.

**Philosophy**: Principles are technology-agnostic where possible. swift-bitcoinkernel is a **thin, disciplined wrapper** over a battle-tested C++ codebase — **correctness, resource safety, Swift-native ergonomics, and operational clarity** take precedence over feature breadth. Where Bitcoin Core already solves a problem, the Swift layer MUST defer to it rather than reimplement.

**Ecosystem Documents**: Repository-level guidance in this file is complemented by the authoritative org-level documents at <https://github.com/21-DOT-DEV/.github>, including `CONTRIBUTING.md` (branching and commit guidelines) and `SECURITY.md` (vulnerability disclosure). This constitution does not duplicate that guidance.

---

## Core Principles

### I. Scope & Bitcoin Core Alignment

**Statement**: The package MUST focus exclusively on wrapping Bitcoin Core for embedded use: daemon lifecycle, consensus validation (`libbitcoinkernel`), and RPC access. Bitcoin Core MUST remain the sole source of consensus and node behavior. Runtime dependencies MUST be drawn from a small, explicit allowlist.

**Rationale**: Keeping scope tight reduces complexity and maintenance burden. Aligning with Bitcoin Core ensures consensus compatibility and leverages decades of battle-tested production code. Divergence from upstream — including alternative consensus logic or bespoke node implementations — risks subtle bugs that affect real money.

**Practices**:
- **MUST** limit scope to wrapping Bitcoin Core: embedded daemon, `libbitcoinkernel` validation, typed RPC client, RPC response models, and associated primitives.
- **MUST** use Bitcoin Core as the sole source of consensus and node logic.
- **MUST** track Bitcoin Core via a specific pinned tag/commit in `subtree.yaml` managed by `swift-plugin-subtree`.
- **MUST** limit runtime dependencies to the following allowlist:
  - `swift-boost` — header-only Boost modules required by Bitcoin Core
  - `swift-event` — `libevent`, required by Bitcoin Core
  - System `sqlite3` — required by Bitcoin Core wallet backend
- **MUST NOT** add runtime dependencies outside the allowlist without a constitutional amendment (MAJOR version bump) that records the justification.
- **MUST NOT** reimplement Bitcoin consensus rules, validation logic, or P2P protocol behavior in Swift.
- **MUST NOT** hand-edit files under `Vendor/bitcoin/` or extracted `Sources/{bitcoind,libbitcoinkernel,crc32c,leveldb,minisketch,secp256k1}/`; changes are overwritten on next extraction. Local modifications required for SPM or embedded use MUST be maintained as patches under `patches/bitcoin/` and reapplied explicitly (see Implementation Guidance).
- **SHOULD** prefer upgrading the pinned Bitcoin Core tag over carrying local divergence.
- **SHOULD** document Bitcoin Core version compatibility in README.
- **MAY** evaluate additional runtime dependencies (e.g., `BerkeleyDB` for legacy wallet support) via constitutional amendment when scope genuinely requires.

**Compliance**: PRs adding new runtime dependencies, new protocol surface, or local patches to vendored sources MUST cite the governing upstream spec or the concrete SPM/embedding need and MUST include constitutional review. CI blocks unapproved additions.

---

### II. C++ Interop & Resource Safety

**Statement**: All Swift ↔ C++ interoperability MUST be implemented safely, with clear ownership semantics, proper memory management, explicit unsafe boundaries, and no propagation of C++ exceptions into Swift. Resources acquired across the boundary (memory, file handles, database handles) MUST have deterministic lifetimes.

**Rationale**: C++ interop is inherently unsafe. Bitcoin Core manages significant resources (multi-GB UTXO set, LevelDB handles, network sockets, wallet DBs) that leak or corrupt silently when lifetimes are wrong. Preventing these errors by construction is dramatically cheaper than debugging them in production nodes holding real money.

**Practices**:
- **MUST** use Swift's C++ interoperability mode (`.interoperabilityMode(.Cxx)`) for all Bitcoin Core bindings.
- **MUST** document memory ownership at every Swift/C++ boundary where it is non-obvious.
- **MUST** catch C++ exceptions at the Swift boundary and convert them to strongly-typed Swift errors; C++ exceptions MUST NOT propagate into Swift code.
- **MUST** validate data crossing the Swift/C++ boundary (null checks, size checks, enum-range checks) before dereferencing.
- **MUST** isolate unsafe code behind clearly named abstractions; downstream Swift callers of the public API MUST NOT need to reason about C++ lifetimes.
- **MUST** ensure C++ objects with nontrivial destructors are released in `deinit` or via explicit `close()`-style methods when ownership is held by Swift.
- **MUST NOT** expose raw C++ pointers, references, or types (`OpaquePointer`, C++ class instances) through public Swift API surface.
- **MUST NOT** rely on ARC alone for C++ resources that carry external side effects (open file descriptors, locked mutexes, held database handles) — pair with explicit release.
- **SHOULD** prefer value types and copying over shared mutable state across the boundary.
- **SHOULD** compile cleanly under `swiftLanguageModes: [.v6]` with strict concurrency checking; upgrade from SHOULD to MUST once verified across all targets.
- **MAY** provide clearly-named unsafe escape hatches for expert users who need raw access.

**Compliance**: Code review MUST verify memory safety and exception handling at C++ boundaries. Tests MUST cover error branches and cleanup paths for resource-acquiring APIs.

---

### III. Node Lifecycle & Shutdown Safety

**Statement**: The embedded Bitcoin Core node MUST expose a well-defined lifecycle with safe initialization, observable state transitions, and deterministic shutdown semantics. The node MUST be restartable in-process without corruption.

**Rationale**: An embedded full node manages significant on-disk state (block storage, chainstate DB, wallet DB, logs). Silent corruption during startup or shutdown can leave databases in unrecoverable states. Restartability matters because applications (especially on iOS) may need to stop and restart the node in response to OS lifecycle events without tearing down the host process.

**Practices**:
- **MUST** expose node state (e.g., `Uninitialized`, `Initializing`, `Syncing`, `Ready`, `ShuttingDown`) to callers via a documented type.
- **MUST** validate configuration before node initialization and surface errors as typed Swift errors.
- **MUST** support graceful shutdown that flushes state and releases resources (chainstate, wallet DBs, P2P connections, RPC server).
- **MUST** support in-process restart: after a clean shutdown, a subsequent start MUST succeed without reboot of the host process (covered by local patches `rpc-server-reset` and `shutdown-reset` — see Implementation Guidance).
- **MUST** handle unexpected termination safely; restarts MUST NOT corrupt block storage or chainstate.
- **MUST** support regtest mode for deterministic testing without network access.
- **MUST NOT** allow RPC calls before the node reaches a state where they are safe (read-only RPCs MAY be allowed during `Syncing`; wallet-affecting RPCs MUST NOT run before `Ready`).
- **MUST NOT** allow multiple concurrent node instances in the same process without explicit opt-in configuration (data-directory isolation).
- **SHOULD** provide sync-progress callbacks during Initial Block Download.
- **SHOULD** document lifecycle expectations (thread-safety, re-entrancy) for every public API touching the node.
- **MAY** provide headless/server deployment helpers.

**Node States** (reference):

| State | Description | Allowed Operations |
|-------|-------------|--------------------|
| Uninitialized | Node not started | Configure, Initialize |
| Initializing | Loading blockchain data | Query progress |
| Syncing | Initial Block Download in progress | Read-only RPC, query progress |
| Ready | Fully synced and operational | All RPC operations |
| ShuttingDown | Graceful shutdown in progress | None |

**Compliance**: Integration tests MUST verify lifecycle transitions including graceful shutdown and in-process restart on both macOS and Linux. CI runs regtest lifecycle smoke tests on every PR.

---

### IV. API Design & RPC Surface

**Statement**: Public Swift APIs MUST follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) with a Swift-native, async/await-first surface and strongly-typed errors. The RPC client MUST provide typed access to Bitcoin Core's published RPC methods while preserving raw JSON-RPC passthrough for methods not (yet) covered.

**Rationale**: Familiar Swift-native design lowers learning curve, improves tooling (autocomplete, DocC, type-system errors), and reduces misuse. A dual typed-plus-passthrough RPC model means users are never blocked by missing wrappers while still benefiting from type-safety for the common path.

**Practices — Swift API**:
- **MUST** follow the Swift API Design Guidelines (naming, argument labels, initializer vs. factory conventions).
- **MUST** use Swift types (`Data`, `String`, `Decimal`, `Date`, `Result`, `async/await`) over C++ equivalents in public API.
- **MUST** namespace types appropriately (e.g., `BTCAmount`, `RPCClient`, `RPCError`, `LastProcessedBlock`, `UnixTimestamp`).
- **MUST** use strongly-typed errors; error descriptions MUST NOT leak secret material (wallet passphrases, private keys, RPC credentials).
- **MUST** provide async/await APIs for any operation that performs I/O or long-running computation; synchronous facades MAY wrap them but MUST NOT be the only surface.
- **MUST** document every public type and function with DocC doc comments (`///`).
- **MUST NOT** expose C++ types, implementation details, or Bitcoin Core internals through the public API surface.
- **SHOULD** provide Swift-native conformances (`Identifiable`, `Hashable`, `Codable`, `Sendable`) where semantically correct.
- **SHOULD** use package traits (e.g., the `wallet` trait) for optional functionality consumers opt into, rather than splitting into separate products.

**Practices — RPC surface**:
- **MUST** provide typed Swift wrappers for the stable public RPC methods of the pinned Bitcoin Core release; methods lacking wrappers are tracked as follow-up work, not design deviations.
- **MUST** provide a raw JSON-RPC passthrough affordance so every Bitcoin Core RPC method (including not-yet-typed and private methods) is reachable without waiting for a wrapper.
- **MUST** preserve Bitcoin Core RPC error codes in the Swift error types so callers can branch on them.
- **MUST** document the pinned Bitcoin Core release the typed wrappers are verified against (e.g., v31.x).
- **SHOULD** organize typed wrappers by Bitcoin Core's own RPC categories (Blockchain, Wallet, Raw Transactions, Network, Util, Mining, Control, Generating).
- **SHOULD** organize typed response models in a dedicated `Models/` subdirectory of the `Bitcoin` target to keep them discoverable independent of RPC client code.
- **MAY** provide convenience methods for common Bitcoin wallet patterns that compose typed RPC calls.

**Compliance**: Code review enforces API naming, error typing, documentation, and the typed-plus-passthrough contract. New typed RPC methods MUST ship with corresponding model tests.

---

### V. Spec-First & Test-Driven Development

**Statement**: Every feature MUST begin with a specification. Implementation MUST follow test-driven development: tests written first, verified to fail, then code written to make them pass.

**Rationale**: Specifications force alignment with users and provide measurable acceptance criteria. TDD prevents regressions, enables confident refactoring across the Swift/C++ boundary, and documents intended behavior for future contributors.

**Practices — Specification Requirements**:
- **MUST** create `spec.md` for every feature before development begins.
- **MUST** scope each spec to a single feature or small, independently-testable sub-feature.
- **MUST** define user scenarios, acceptance criteria, and success metrics in user-facing terms.
- **MUST NOT** combine multiple unrelated features in one spec.
- **MUST NOT** describe implementation details in place of behavior.

**Practices — Test-Driven Development**:
- **MUST** write tests before implementation (red → green → refactor).
- **MUST** verify tests fail before the implementing change lands.
- **MUST** maintain separate test tiers (below).
- **MUST** validate RPC decoding against fixtures derived from Bitcoin Core's functional test suite where available (`Tests/BitcoinTests/Fixtures/`).
- **SHOULD** develop outside-in, starting from the caller's perspective.
- **MAY** add property-based tests for parser and state-machine components where they add value beyond fixture-based coverage.

**Testing Tiers**:

| Tier | Type | Runs | Requirement |
|------|------|------|-------------|
| MUST | Unit tests | Every PR | Swift logic, parsing, type conversions, error mapping, RPC-model decoding |
| MUST | Regtest smoke tests | Every PR | Node init / shutdown / restart, basic RPC calls |
| SHOULD | Regtest integration | Scheduled / pre-release | Full RPC coverage, wallet operations, edge cases |
| SHOULD | Upstream test vectors | Bitcoin Core bumps | Validate against Bitcoin Core functional-test data |

**Compliance**: PRs MUST include tests written first. PRs that ship code without corresponding tests, or whose tests pass on the first commit before the implementation exists, MUST be rejected in review. Specs that combine multiple unrelated features MUST be rejected in review.

---

### VI. Cross-Platform CI & Quality Gates

**Statement**: The package MUST build and (where applicable) test cleanly on all Tier 1 platforms. Platform support is tiered normatively: Tier 1 is CI-gated and blocks merges; Tier 2 is aspirational and does not block merges. Behavior MUST be deterministic within the guarantees Bitcoin Core provides.

**Rationale**: Cross-platform reliability is a core value proposition. Enforcing a tiered model keeps the merge gate honest (we only block on platforms we actually verify) while leaving room for ambitious platform expansion without constitutional churn.

**Platform Tiers**:

| Tier | Platforms | CI Requirement |
|------|-----------|----------------|
| **Tier 1** (MUST, blocking) | macOS 15+ (arm64, x86_64); iOS 18+ (arm64); Linux (Ubuntu 22.04+, x86_64, arm64) | Build + run tests |
| **Tier 2** (aspirational) | tvOS 18+; visionOS 2+; watchOS; Windows; Android | SHOULD compile; best-effort; failures do not block merge |

**Practices**:
- **MUST** build and run tests on every Tier 1 platform on every PR.
- **MUST** ensure deterministic behavior: given the same inputs, Bitcoin Core + swift-bitcoinkernel produce the same outputs across all Tier 1 platforms.
- **MUST** pass all Tier 1 unit and regtest smoke tests before merge.
- **MUST** enforce linting (SwiftLint, SwiftFormat) as merge gates once the infrastructure is in place.
- **MUST NOT** merge code that breaks any Tier 1 platform.
- **SHOULD** exercise Tuist-managed integration builds in `Projects/` as part of pre-release validation (see Implementation Guidance).
- **SHOULD** attempt Tier 2 platform builds on a scheduled cadence to surface regressions; failures report informationally and do not block merge.
- **SHOULD** document platform-conditional behavior (iOS network-interface shims, restart semantics) in public doc comments.
- **MAY** promote a Tier 2 platform to Tier 1 via a MINOR constitutional amendment once CI coverage and any required patches are in place.
- **MAY** demote a Tier 1 platform to Tier 2 only via a MAJOR constitutional amendment with concrete justification (e.g., upstream Bitcoin Core drops support).

**Compliance**: CI pipeline enforces every MUST in this principle. Tier 1 build or test failures block merge. Tier 2 results are reported informationally.

---

### VII. Open Source Excellence

**Statement**: All development MUST follow open-source best practices: clear documentation, correct licensing and attribution, and code that favors readability over cleverness. Contribution and security-disclosure guidance MUST be deferred to the authoritative org-level documents.

**Rationale**: swift-bitcoinkernel sits in an ecosystem where users evaluate library trust (correctness, maintenance responsiveness, honest framing) before adopting it, especially for Bitcoin software handling real funds. Good documentation, responsive maintenance, and clear licensing lower adoption friction and increase the chance that security-relevant feedback reaches the maintainer.

**Practices**:
- **MUST** include a LICENSE file (MIT) for swift-bitcoinkernel's own code.
- **MUST** preserve and attribute the upstream Bitcoin Core license(s) shipped under `Vendor/bitcoin/`.
- **MUST** maintain a README with setup, supported platforms, a Quick Start, RPC coverage summary, and pinned Bitcoin Core version.
- **MUST** defer contribution guidelines to the org-level [CONTRIBUTING.md](https://github.com/21-DOT-DEV/.github/blob/main/CONTRIBUTING.md) (branching and commit guidelines apply).
- **MUST** defer security disclosure to the org-level [SECURITY.md](https://github.com/21-DOT-DEV/.github/blob/main/SECURITY.md).
- **MUST** document every public API with DocC doc comments (`///`).
- **MUST** apply KISS and DRY principles; favor readable code over clever code.
- **MUST** preserve an `AGENTS.md` (root) capturing non-obvious patterns for AI and human agents, including the vendored-sources rule and the patches discipline.
- **MUST** include at least one minimal, complete example per major API family (embedded-daemon bootstrap, RPC query, transaction building).
- **SHOULD** maintain scoped `AGENTS.md` files (e.g., `Projects/AGENTS.md`) for directory-specific deltas.
- **SHOULD** provide issue and PR templates.
- **SHOULD** respond to community contributions and security reports promptly and respectfully.
- **MAY** expand examples and tutorials as APIs stabilize.

**Compliance**: PRs MUST include documentation updates for new features or API changes. Code reviewers enforce readability and alignment with the documented layering.

---

## Implementation Guidance

### Security Disclosure Process

**Authoritative source**: <https://github.com/21-DOT-DEV/.github/blob/main/SECURITY.md>

This repository defers to the org-level `SECURITY.md` for vulnerability reporting, contact methods, response timelines, and coordinated disclosure. This constitution MUST NOT duplicate that guidance; amendments to disclosure process are made in the org-level document.

**Upstream coordination**: For vulnerabilities originating in `Vendor/bitcoin/` (i.e., upstream Bitcoin Core), maintainers SHOULD coordinate disclosure with the Bitcoin Core security process in addition to the org-level process.

---

### Vendored Upstream Sync

**Purpose**: Bitcoin Core sources live under `Vendor/bitcoin/` and are extracted into `Sources/{bitcoind,libbitcoinkernel,crc32c,leveldb,minisketch,secp256k1}/` and selected test fixtures via the `subtree` CLI, configured in `subtree.yaml`.

**Requirements**:
- **MUST** pin a specific upstream commit and tag in `subtree.yaml` (current: `v31.0rc4`).
- **MUST** treat files under `Vendor/**` and extracted `Sources/{bitcoind,libbitcoinkernel,crc32c,leveldb,minisketch,secp256k1}/` as read-only with respect to local edits; any required modification MUST be applied as a patch (see Local Patches Discipline) or via the extraction configuration.
- **MUST** record the upstream revision / tag being extracted in the commit that performs the extraction.
- **MUST** run the full Tier 1 CI matrix after every subtree re-extraction or upstream bump.
- **SHOULD** prefer upstreaming fixes to Bitcoin Core over carrying local divergence.
- **SHOULD** capture the rationale for each extraction pattern or exclusion in comments inside `subtree.yaml`.
- **SHOULD** bump Bitcoin Core promptly for security advisories.

---

### Local Patches Discipline

**Purpose**: Certain SPM-build and embedded-use concerns cannot be resolved by extraction configuration alone. The `patches/` directory tracks these as first-class, reviewable artifacts — following the [Bitcoin Core `depends/patches/` convention](https://github.com/bitcoin/bitcoin/tree/master/depends/patches).

**Current patches** (see `patches/README.md`):

| # | Patch | Upstream file | Purpose |
|---|-------|---------------|---------|
| 1 | `patches/bitcoin/ios-netif-guard.md` | `src/common/netif.cpp` | Narrow `__APPLE__` to macOS (`TARGET_OS_OSX`); iOS returns `nullopt` |
| 2 | `patches/bitcoin/rpc-server-reset.md` | `src/rpc/server.{cpp,h}` | Remove one-shot `std::once_flag`; enable RPC restart |
| 3 | `patches/bitcoin/shutdown-reset.md` | `src/init.cpp` | Reset four globals to enable in-process `bitcoind_main()` restart |
| 4 | `patches/bitcoin/main-function-guard.md` | `src/bitcoind.cpp` | `MAIN_FUNCTION` define enabling rename of `main()` to `bitcoind_main()` |

**Non-patch custom files** (SPM build-config replacements, not upstream modifications):

- `Sources/bitcoind/include/bitcoin-build-config.h`
- `Sources/libbitcoinkernel/src/bitcoin-build-config.h`

**Requirements**:
- **MUST** document every local patch under `patches/<upstream>/<name>.md` with problem statement, fix description, and upstream status (filed issue, PR link, or rationale for carrying locally).
- **MUST** reapply patches after every subtree extraction; extraction MUST NOT silently drop them.
- **MUST** justify each patch against an SPM-build, iOS-embedding, or restart-semantics need; patches MUST NOT be used to add features that belong upstream.
- **SHOULD** upstream patches to Bitcoin Core where applicable and record the PR link in the patch document.
- **SHOULD** re-evaluate every patch on each Bitcoin Core bump; remove patches obsoleted by upstream fixes.

---

### Tuist Projects Folder

**Purpose**: `Projects/` hosts a Tuist-managed Xcode workspace with two SwiftUI demo apps (`NodeApp`, `KernelApp`) and their test bundles, layered on the SPM package for cross-platform integration validation that exercises swift-bitcoinkernel in a real app context beyond SPM's capabilities.

**Workflow** (from `Projects/AGENTS.md`):

```bash
# Generate
swift package --disable-sandbox tuist generate -p Projects/ --no-open

# Build or test a demo app on a platform (CI-matching)
swift package --disable-sandbox tuist build NodeApp -p Projects/ --platform macos
swift package --disable-sandbox tuist test KernelApp -p Projects/ --platform ios
```

**Requirements**:
- **MUST** keep `Projects/` schemes synchronized with the SPM targets they consume.
- **MUST** build and test both demo apps (`NodeApp`, `KernelApp`) on macOS and iOS in CI via `.github/workflows/tuist-apps.yml`; keep that workflow's platform matrix synchronized with this guidance.
- **MUST** ensure the workspace's combined dependency graph resolves — the root package and `Projects/Project.swift`'s `swift-tor` pin MUST agree on shared transitive versions (e.g. `swift-event`).
- **MUST** document the workflow in `Projects/README.md` and `Projects/AGENTS.md`.
- **SHOULD** prefer Tuist-based builds over raw `xcodebuild` where available (matches CI).

---

## Technology Stack (Current Implementation)

**Note**: The constitution defines technology-agnostic principles. This section documents current choices, which may change without constitutional amendments so long as the principles above continue to hold.

### Supported Platforms

**Tier 1** (MUST, CI-gated):
- **macOS** 15+ (arm64, x86_64)
- **iOS** 18+ (arm64)
- **Linux** (Ubuntu 22.04+, x86_64, arm64)

**Tier 2** (aspirational, non-blocking):
- **tvOS** 18+ — pending verification that C++20 Bitcoin Core builds within Apple's UNIX-primitive restrictions
- **visionOS** 2+ — same verification pending
- **watchOS** — resource constraints; aspirational only
- **Windows** — different C++ toolchain; aspirational only
- **Android** — NDK complexity; aspirational only

### Current Stack (2026-05-03)

| Category | Choice |
|----------|--------|
| Language | Swift 6.3 (swift-tools-version) |
| C Standard | C89 |
| C++ Standard | C++20 |
| Interop | `.interoperabilityMode(.Cxx)` |
| Build | Swift Package Manager (SPM) |
| Testing | swift-testing, XCTest |
| Integration | Tuist (in `Projects/`) |
| Linting | SwiftLint, SwiftFormat (planned) |
| CI | GitHub Actions (Apple + Linux) |
| Upstream management | `swift-plugin-subtree` |
| Upstream Bitcoin Core | v31.0rc4 (pinned in `subtree.yaml`) |

### Products

| Product | Type | Description |
|---------|------|-------------|
| `Bitcoin` | Swift library | High-level API: `RPCClient` + embedded daemon bridge |
| `BitcoinKernel` | Swift library | Low-level bindings to `libbitcoinkernel` for consensus validation |

### Package Traits

| Trait | Default | Effect |
|-------|---------|--------|
| `wallet` | off | Enables wallet features in the `Bitcoin` target (defines `ENABLE_WALLET`) |

### Runtime Dependencies (allowlist per Principle I)

- `swift-boost` — Boost header-only modules required by Bitcoin Core CMake
- `swift-event` — `libevent`, required by Bitcoin Core
- System `sqlite3` — linked for wallet backend

### Internal C / C++ Targets (compiled from vendored sources, not runtime dependencies)

- `bitcoind` — Bitcoin Core daemon sources
- `libbitcoinkernel` — consensus-validation library
- `crc32c`, `leveldb`, `minisketch`, `secp256k1` — vendored C/C++ libraries required by Bitcoin Core

### Development-only Dependencies

- `swift-plugin-tuist` — Tuist integration for `Projects/`
- `swift-plugin-subtree` — vendored-source sync
- `swift-docc-plugin` — DocC archive generation

### Upstream

- **Bitcoin Core**: <https://github.com/bitcoin/bitcoin> (pinned in `subtree.yaml`)

---

## Governance

### Authority

This constitution supersedes all other development practices for this repository. Deviations MUST be explicitly justified and approved.

**Model**: Project owner (BDFL) can amend the constitution directly. Community proposes changes via GitHub issues and pull requests.

### Security-Relevant Changes

Changes that affect consensus behavior, node lifecycle, resource safety at the C++ boundary, RPC authentication / credentials, or vendored Bitcoin Core require additional scrutiny:

| Requirement | Purpose |
|-------------|---------|
| Document security implications in the PR description | Creates an audit trail |
| 48–72 hour merge delay | Allows community review |
| Explicit "security-reviewed" label | Signals deliberate review |

**Security-relevant changes include**:
- Bitcoin Core version bumps (especially those addressing upstream CVEs)
- Changes to the C++ / Swift boundary or resource-ownership semantics
- Changes to node lifecycle, shutdown, or restart logic
- Changes to RPC authentication, credential handling, or error descriptions
- Changes to or additions of patches under `patches/`

### Amendment Process

1. Project owner proposes an amendment with rationale and impact analysis.
2. Version updated per [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html):
   - **MAJOR**: Backward-incompatible changes, principle removals, platform-tier demotions, or new runtime dependencies outside the allowlist.
   - **MINOR**: New principle, platform-tier promotion (Tier 2 → Tier 1), or materially expanded guidance.
   - **PATCH**: Clarifications, wording fixes, non-semantic refinements.
3. Update dependent templates in `.specify/templates/` as needed.
4. Document the change in the Sync Impact Report at the top of this file.
5. Commit with a descriptive message.

### Compliance Review Triggers

| Trigger | Action |
|---------|--------|
| Adding a runtime dependency outside the allowlist | Full constitutional amendment (MAJOR) required |
| Bitcoin Core upstream bump | Vendored-upstream review + security check |
| Adding, modifying, or removing a patch under `patches/` | Constitutional review + security-relevant change protocol |
| New platform support (Tier 2 → Tier 1 promotion) | MINOR amendment + CI coverage gate |
| Breaking API changes (post-1.0) | Stability-signalling review required |
| Changes to the C++ boundary or node lifecycle | Security review + resource-safety audit |

### Versioning & Stability

**Pre-1.0** (current):
- No stability guarantees.
- Immediate breaking changes acceptable.
- Users advised to pin exact versions (e.g., `.exact("0.x.y")`).

**Post-1.0** (future):
- Semantic versioning strictly enforced.
- Deprecation period (one minor version) before removal of public API.
- Breaking changes require a major version bump.

**Minimum Swift Tools Version**: 6.3 (as declared in `Package.swift`).

### Enforcement

- PR reviewers verify constitutional alignment.
- CI pipeline enforces MUST-level (blocking) and SHOULD-level (warning) gates.
- Three-tier enforcement:
  - **MUST**: Blocks merge.
  - **SHOULD**: Warning; requires override justification in the PR description.
  - **MAY**: Informational only.

---

## Version History

**Version**: 2.1.0
**Ratified**: 2026-05-03
**Last Amended**: 2026-05-31

**Changelog**:
- **2.1.0** (2026-05-31): **MINOR** — expanded Tuist Projects Folder guidance (Implementation Guidance). Added a normative CI mandate to build and test both demo apps (`NodeApp`, `KernelApp`) on macOS and iOS via `.github/workflows/tuist-apps.yml`, plus a dependency-graph-resolution requirement. Corrected stale example commands (previously built the `Bitcoin`/`BitcoinKernel` products and tested `Bitcoin-Workspace`; now per-app schemes) and the Purpose line (dropped an inapplicable "XCFramework workflows" reference inherited from the sibling canon — `Projects/` hosts demo apps). Companion repo change: `Projects/Project.swift` `swift-tor` pin bumped `0.1.0 → 0.1.1` to align `swift-event` at `0.2.1` with the root package, unbreaking `tuist generate`.
- **2.0.0** (2026-05-03): **MAJOR rewrite** adopting the 7-principle sibling canon (swift-secp256k1 / swift-tor / swift-event / swift-openssl). Structural changes: consolidated 8 principles → 7 (merged "RPC Client Design & Reliability" + "API Design & Swift Idioms" → "API Design & RPC Surface"); renamed "C++ Interoperability & Memory Safety" → "C++ Interop & Resource Safety" and "Node Lifecycle Management" → "Node Lifecycle & Shutdown Safety". New structural elements: runtime-dependency allowlist with MAJOR-amendment gate (Principle I); tiered platform model with Tier 1 (macOS 15+ / iOS 18+ / Linux) and Tier 2 (tvOS / visionOS / watchOS / Windows / Android) (Principle VI); local-patches discipline codified (Principle I + Implementation Guidance); org-level CONTRIBUTING.md / SECURITY.md deferral to 21-DOT-DEV/.github (Principle VII); Compliance Review Triggers table (Governance). Alignment corrections: platform scope now matches `Package.swift` (macOS 15+ / iOS 18+, Linux added per maintainer direction); Bitcoin Core pin updated to v31.0rc4; products corrected to `Bitcoin` + `BitcoinKernel` (internal C++ targets: `bitcoind`, `libbitcoinkernel`, `crc32c`, `leveldb`, `minisketch`, `secp256k1`); wallet documented as package trait rather than separate library; Swift tools version 6.3 / C++20 recorded in Technology Stack.
- **1.0.0** (2025-12-05): Initial constitution with 8 core principles, three-tier enforcement, BDFL governance, tiered platform support, tiered RPC coverage model. Superseded by v2.0.0.

---

## Appendix: Principle Mapping

This constitution organizes swift-bitcoinkernel-specific concerns on top of the shared sibling canon:

- Scope, upstream alignment, runtime-dependency allowlist, local-patches discipline → **Principle I**
- C++ memory safety, exception handling, resource lifetimes, Swift concurrency → **Principle II**
- Embedded daemon state machine, shutdown / restart semantics, regtest support → **Principle III**
- Swift-native API, typed errors, RPC typed-plus-passthrough, package traits → **Principle IV**
- Spec-first workflow, TDD tiers, upstream test vectors → **Principle V**
- Tier 1 / Tier 2 platforms, deterministic behavior, Tuist integration → **Principle VI**
- README / AGENTS / docs / examples / org-level deferrals → **Principle VII**
- Vulnerability disclosure, upstream coordination → **Implementation Guidance** (org-level pointer)
- Stability posture, amendment process, enforcement tiers → **Governance**

**Sibling cross-references** (patterns borrowed):

- **swift-secp256k1 v1.0.0** → 7-principle structure, three-tier enforcement, Tuist `Projects/`, Appendix pattern, BDFL governance, pre-1.0 stability posture, shared Principle V language
- **swift-tor v1.1.0** → runtime-dependency allowlist (MAJOR-amendment gate), Compliance Review Triggers table, narrow-scope framing ("no consensus reimplementation")
- **swift-event v1.0.1** → two-layer API design (`BitcoinKernel` + `Bitcoin`), Swift 6 strict-concurrency reference, Swift API Design Guidelines citation, SemVer 2.0.0 citation
- **swift-openssl v1.0.1** → org-level CONTRIBUTING.md / SECURITY.md deferrals, CI workflow enumeration pattern, Sync Impact Report format

**Version**: 2.1.0 | **Ratified**: 2026-05-03 | **Last Amended**: 2026-05-31
