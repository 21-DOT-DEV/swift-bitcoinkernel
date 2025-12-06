<!--
Sync Impact Report:
- Version: N/A → 1.0.0 (Initial constitution)
- Change Type: Initial creation
- Scope: swift-bitcoin monorepo (/Users/csjones/Developer/swift-bitcoin)
- Structure: Two-tier (8 core principles + implementation practices in nested format)
- Core Principles:
  I. Scope & Bitcoin Core Alignment
  II. C++ Interoperability & Memory Safety
  III. RPC Client Design & Reliability
  IV. API Design & Swift Idioms
  V. Node Lifecycle Management
  VI. Spec-First & Test-Driven Development
  VII. Cross-Platform CI & Quality Gates
  VIII. Open Source Excellence
- Enforcement: Three-tier model (MUST/SHOULD/MAY) with explicit MUST NOT
- Governance: BDFL model
- Compliance: Continuous CI + event-driven strategic review
- Templates Status:
  ⚠ spec-template.md - Requires alignment review
  ⚠ plan-template.md - Requires alignment review
  ⚠ tasks-template.md - Requires alignment review
  ⚠ checklist-template.md - Requires alignment review
- Follow-up TODOs:
  • Create CONTRIBUTING.md with workflow details
  • Create SECURITY.md with vulnerability disclosure process
  • Create subtree.yaml for Bitcoin Core upstream tracking
-->

# Constitution for swift-bitcoin

## Preamble

This constitution governs the **swift-bitcoin** package, a Swift wrapper around Bitcoin Core's C++ implementation providing embedded node functionality and high-level RPC access.

**Scope**: This repository only. Covers the `Bitcoin` Swift library, C++ bindings (`bitcoind`, `leveldb`, `secp256k1`, `minisketch`, `crc32c`), and associated tooling.

**Philosophy**: Principles are technology-agnostic where possible. This is a Bitcoin Core wrapper—correctness, reliability, and Swift-native ergonomics take precedence over features. The C++ implementation drives core logic; Swift provides safe, idiomatic access.

**Intended Audience**: Developers building Bitcoin wallets/applications, researchers exploring Bitcoin internals, and production services requiring Bitcoin RPC in Swift environments.

---

## Core Principles

### I. Scope & Bitcoin Core Alignment

**Statement**: The package MUST focus exclusively on wrapping Bitcoin Core functionality: embedded node operation, RPC access, and related primitives. Bitcoin Core is the sole source of consensus and node logic.

**Rationale**: Keeping scope tight reduces complexity. Aligning with Bitcoin Core ensures consensus compatibility and leverages battle-tested implementation.

**Practices**:
- **MUST** limit scope to Bitcoin Core wrapper functionality: embedded node, RPC client, blockchain queries
- **MUST** use Bitcoin Core as the sole source of consensus logic—no reimplementation
- **MUST** track Bitcoin Core releases via pinned commits in `subtree.yaml` using swift-plugin-subtree
- **MUST** maintain strict minimal dependencies; only dependencies required by Bitcoin Core itself
- **MUST NOT** add dependencies without constitutional review and explicit justification
- **MUST NOT** reimplement Bitcoin consensus rules or validation logic in Swift
- **SHOULD** monitor upstream Bitcoin Core releases via CI for security patches and new features
- **SHOULD** document Bitcoin Core version compatibility in README
- **MAY** add swift-nio in future for enhanced networking features (requires constitutional review)

**Compliance**: PRs adding new dependencies MUST include justification and constitutional review. CI tracks upstream Bitcoin Core releases.

---

### II. C++ Interoperability & Memory Safety

**Statement**: All C++ interoperability MUST be implemented safely, with clear ownership semantics, proper memory management, and explicit unsafe boundaries.

**Rationale**: C++ interop is inherently unsafe. Careful boundary management prevents memory corruption, leaks, and undefined behavior that could compromise node integrity or security.

**Practices**:
- **MUST** use Swift's C++ interoperability mode (`interoperabilityMode(.Cxx)`) for all bindings
- **MUST** document memory ownership at every Swift/C++ boundary
- **MUST** ensure C++ objects are properly initialized before use and cleaned up after
- **MUST** isolate unsafe code to clearly marked boundaries
- **MUST** validate all data crossing the Swift/C++ boundary
- **MUST NOT** expose raw C++ pointers through public Swift APIs
- **MUST NOT** allow C++ exceptions to propagate into Swift (catch and convert to Swift errors)
- **SHOULD** prefer value types and copying over shared mutable state across boundaries
- **SHOULD** use Swift's automatic reference counting where possible for C++ object lifetimes
- **MAY** provide unsafe escape hatches for expert users, clearly documented as such

**Compliance**: Code review MUST verify memory safety at C++ boundaries. CI runs address sanitizer on supported platforms.

---

### III. RPC Client Design & Reliability

**Statement**: The RPC client MUST provide reliable, typed access to Bitcoin Core functionality with clear error handling and timeout behavior.

**Rationale**: RPC is the primary interface for users. Reliability and clear error semantics are critical for wallet applications and production services.

**Practices**:
- **MUST** provide fully-typed Swift wrappers for core RPC methods (blockchain info, transactions, blocks)
- **MUST** provide raw JSON-RPC passthrough for all methods (users never blocked by missing wrappers)
- **MUST** use `Bitcoin.Error` enum with clear categories (node configuration, RPC errors)
- **MUST** preserve Bitcoin Core RPC error codes in error types for debugging
- **MUST** handle connection failures, timeouts, and malformed responses gracefully
- **MUST NOT** leak sensitive information (credentials, private keys) in error descriptions
- **SHOULD** type extended RPC methods progressively (wallet, network, mining)
- **SHOULD** document which RPC methods have typed wrappers vs passthrough-only
- **MAY** provide convenience methods for common Bitcoin wallet use cases

**RPC Coverage Tiers**:
| Tier | Coverage | Requirement |
|------|----------|-------------|
| Core | Essential methods (getblockchaininfo, getblock, sendrawtransaction, etc.) | MUST have typed wrappers |
| Extended | Additional methods (wallet, mining, network diagnostics) | SHOULD have typed wrappers |
| Passthrough | All 100+ Bitcoin Core RPC methods | MUST be accessible via raw JSON-RPC |

**Post-1.0 Goal**: Comprehensive typed coverage of all stable Bitcoin Core RPC methods.

**Compliance**: PRs adding new RPC wrappers MUST include tests. Documentation MUST indicate coverage tier.

---

### IV. API Design & Swift Idioms

**Statement**: Public APIs MUST follow Swift conventions, providing safe defaults and idiomatic patterns familiar to Swift developers.

**Rationale**: Swift-native design lowers learning curve, reduces misuse, and enables better tooling support (autocomplete, documentation).

**Practices**:
- **MUST** follow Swift API Design Guidelines (clear naming, argument labels, documentation)
- **MUST** use Swift types (`Data`, `String`, `Result`, `async/await`) over C++ equivalents in public APIs
- **MUST** namespace types appropriately (e.g., `Bitcoin.Block`, `Bitcoin.Transaction`, `Bitcoin.Error`)
- **MUST** provide async/await APIs for all blocking operations
- **MUST** use strongly-typed errors (`Bitcoin.Error`) rather than throwing generic errors
- **MUST NOT** expose C++ types or implementation details in public API surface
- **SHOULD** provide SwiftUI-friendly types where applicable (Identifiable, Hashable, Codable)
- **SHOULD** include DocC documentation for all public types and methods
- **MAY** provide Combine publishers as alternative to async/await for reactive patterns

**Compliance**: Code review enforces API naming conventions and Swift idioms. Linting checks documentation coverage.

---

### V. Node Lifecycle Management

**Statement**: The embedded Bitcoin Core node MUST have well-defined lifecycle states with safe initialization, operation, and shutdown semantics.

**Rationale**: An embedded node manages significant resources (memory, disk, network). Clear lifecycle management prevents resource leaks, corruption, and undefined behavior.

**Practices**:
- **MUST** provide explicit initialization with configuration options (network, data directory, RPC settings)
- **MUST** support graceful shutdown that flushes data and releases resources
- **MUST** handle unexpected termination safely (no data corruption)
- **MUST** expose node state (initializing, syncing, ready, shutting down) to callers
- **MUST** validate configuration before node initialization
- **MUST NOT** allow RPC calls before node is fully initialized
- **MUST NOT** allow multiple node instances in the same process without explicit configuration
- **SHOULD** support regtest mode for testing without network access
- **SHOULD** provide sync progress callbacks during Initial Block Download (IBD)
- **MAY** support headless operation for server deployments

**Node States**:
| State | Description | Allowed Operations |
|-------|-------------|-------------------|
| Uninitialized | Node not started | Configure, Initialize |
| Initializing | Loading blockchain data | Query progress |
| Syncing | Initial Block Download in progress | Read-only RPC, Query progress |
| Ready | Fully synced and operational | All RPC operations |
| ShuttingDown | Graceful shutdown in progress | None |

**Compliance**: Integration tests MUST verify lifecycle transitions. CI runs node lifecycle smoke tests.

---

### VI. Spec-First & Test-Driven Development

**Statement**: Every feature MUST start with a specification. All code MUST follow test-driven development: tests written first, verified to fail, then implementation proceeds.

**Rationale**: Specifications ensure alignment with user needs. TDD prevents regressions, enables confident refactoring, and documents expected behavior.

**Practices - Specification Requirements**:
- **MUST** create `spec.md` for every feature before development
- **MUST** represent a single feature or small subfeature (not multiple unrelated features)
- **MUST** be independently testable (no dependencies on incomplete specs)
- **MUST** define user scenarios, acceptance criteria, and success metrics
- **MUST NOT** combine multiple unrelated features in one spec
- **MUST NOT** describe implementation details instead of user-facing behavior

**Practices - Test-Driven Development**:
- **MUST** write tests before implementation (red → green → refactor)
- **MUST** verify tests fail initially
- **MUST** maintain separate unit and integration tests
- **SHOULD** develop outside-in (user's perspective first)

**Testing Requirements**:
| Tier | Type | Runs | Requirement |
|------|------|------|-------------|
| MUST | Unit tests | Every PR | Swift logic, parsing, type conversions, error mapping |
| MUST | Regtest smoke tests | Every PR | Basic node init/shutdown, simple RPC calls |
| SHOULD | Regtest integration | Scheduled/pre-release | Full RPC coverage, wallet operations, edge cases |
| MAY | Upstream test vectors | Major version bumps | Validate against Bitcoin Core test data |

**Compliance**: PRs MUST include tests written first. CI blocks merges if tests missing or immediately passing.

---

### VII. Cross-Platform CI & Quality Gates

**Statement**: The package MUST maintain support for all Tier 1 platforms with CI coverage ensuring features compile and tests pass on each.

**Rationale**: Cross-platform reliability enables broad adoption. Deterministic behavior is critical for Bitcoin applications where consensus matters.

**Platform Tiers**:
| Tier | Platforms | Requirement |
|------|-----------|-------------|
| Tier 1 | macOS (arm64, x86_64), iOS (arm64), tvOS (arm64), visionOS (arm64), Linux (x86_64, arm64) | MUST compile and pass tests |
| Tier 2 | watchOS, Android, WASM, Windows | MAY have feature limitations; aspirational support |

**Practices**:
- **MUST** test across all Tier 1 platforms in CI
- **MUST** ensure deterministic behavior: same inputs produce same outputs across platforms
- **MUST** pass all unit and regtest smoke tests before merge
- **MUST** pass linting checks (SwiftLint, SwiftFormat) before merge
- **MUST NOT** merge code that breaks any Tier 1 platform
- **SHOULD** run comprehensive integration tests on schedule
- **SHOULD** test on both Intel and ARM architectures for macOS/Linux
- **MAY** provide platform-specific optimizations where beneficial
- **MAY** expand Tier 2 platforms to Tier 1 as support matures

**Compliance**: CI pipeline enforces all MUST-level gates. Platform failures block merge.

---

### VIII. Open Source Excellence

**Statement**: All development MUST follow open source best practices: comprehensive documentation, welcoming contributions, clear licensing, and simplicity over cleverness.

**Rationale**: Good documentation reduces friction. Clear decisions preserve knowledge. Simplicity encourages contributions and reduces maintenance burden.

**Practices**:
- **MUST** document architecture decisions
- **MUST** maintain clear README with setup instructions and usage examples
- **MUST** provide contribution guidelines (CONTRIBUTING.md)
- **MUST** include LICENSE file (MIT)
- **MUST** write clear, human-readable code (readability over cleverness)
- **MUST** apply KISS and DRY principles
- **MUST** document all public APIs with inline comments
- **MUST** include minimal, complete examples for common use cases (node setup, RPC queries, transaction building)
- **SHOULD** maintain security disclosure process (SECURITY.md)
- **SHOULD** provide issue and PR templates
- **SHOULD** respond to community contributions promptly and respectfully

**Compliance**: PRs MUST include documentation updates for new features or API changes. Code reviews enforce readability.

---

## Implementation Guidance

### Error Handling

**Statement**: Errors MUST be strongly typed using a single `Bitcoin.Error` enum covering node configuration and RPC failures.

**Structure**:
```swift
enum Bitcoin.Error: Error {
    // Node lifecycle
    case nodeNotInitialized
    case nodeShutdownFailed(reason: String)
    case configurationInvalid(detail: String)
    
    // RPC layer
    case rpcConnectionFailed
    case rpcTimeout
    case rpcError(code: Int, message: String)  // Bitcoin Core error codes preserved
}
```

**Requirements**:
- **MUST** preserve Bitcoin Core RPC error codes for debugging
- **MUST NOT** leak sensitive information in error descriptions
- **SHOULD** provide actionable error messages for common failures

---

### Upstream Synchronization

**Statement**: Bitcoin Core upstream MUST be tracked via pinned releases using swift-plugin-subtree.

**Requirements**:
- **MUST** maintain `subtree.yaml` with pinned Bitcoin Core commit/tag
- **MUST** review and test upstream updates before merging
- **MUST** document Bitcoin Core version compatibility in README
- **SHOULD** monitor upstream releases via CI for security patches
- **SHOULD** provide migration notes when upstream changes affect Swift APIs

---

### Security Disclosure Process

**Statement**: A clear process for reporting vulnerabilities MUST be documented.

**Requirements**:
- **MUST** provide SECURITY.md with reporting instructions
- **MUST** include preferred contact method (email, encrypted if possible)
- **MUST** define expected response timeline (e.g., acknowledgment within 48 hours)
- **SHOULD** provide PGP key for encrypted reports
- **SHOULD** acknowledge reporters in release notes (with permission)

---

## Technology Stack (Current Implementation)

**Note**: Constitution defines technology-agnostic principles. This section documents current choices, which may change without constitutional amendments.

### Supported Platforms

**Tier 1** (full support):
- **macOS** (arm64, x86_64)
- **iOS** (arm64)
- **tvOS** (arm64)
- **visionOS** (arm64)
- **Linux** (x86_64, arm64)

**Tier 2** (aspirational):
- **watchOS** (arm64) — resource constraints
- **Android** — NDK complexity
- **WASM** — filesystem/networking limitations
- **Windows** — different C++ toolchain

### Current Stack (2025-12-05)

| Category | Choice |
|----------|--------|
| Language | Swift 6.0+ |
| C Standard | C89 |
| C++ Standard | C++17 |
| Build | Swift Package Manager (SPM) |
| Testing | swift-testing, XCTest |
| Linting | SwiftLint, SwiftFormat |
| Upstream Management | swift-plugin-subtree |

### Products

| Product | Type | Description |
|---------|------|-------------|
| `Bitcoin` | Swift library | Primary high-level API |
| `bitcoind` | C++ bindings | Bitcoin Core embedded node |
| `secp256k1` | C bindings | Elliptic curve cryptography |
| `leveldb` | C++ bindings | Database storage |
| `minisketch` | C bindings | Set reconciliation |
| `crc32c` | C bindings | Checksum |

### Dependencies

**Runtime**: Boost.swift, libevent.swift (required by Bitcoin Core)
**Development only**: lefthook-plugin, swift-plugin-tuist, swift-plugin-subtree

---

## Governance

### Authority

This constitution supersedes all other development practices. Deviations MUST be explicitly justified and approved.

**Model**: Project owner (BDFL) can amend constitution directly. Community proposes changes via GitHub issues.

### Amendment Process

1. Project owner proposes amendment with rationale and impact analysis
2. Version updated (semantic versioning):
   - **MAJOR**: Backward-incompatible changes or principle removals
   - **MINOR**: New principle or materially expanded guidance
   - **PATCH**: Clarifications, wording fixes
3. Update dependent templates in `.specify/templates/`
4. Document changes in Sync Impact Report
5. Commit with descriptive message

### Compliance Review Triggers

| Trigger | Action |
|---------|--------|
| Adding new dependencies | Full constitutional alignment check |
| Bitcoin Core upstream updates | Verify behavior consistency |
| Breaking API changes (semver major) | Stability signaling review |
| New platform support | Platform tier evaluation |

### Versioning & Stability

**Pre-1.0** (current):
- No stability guarantees
- Breaking changes acceptable
- Users advised to pin exact versions
- No deprecation period required

**Post-1.0** (future):
- Semantic versioning strictly enforced
- Deprecation period (one minor version) before removal
- Breaking changes require major version bump
- Goal: comprehensive RPC coverage

**Minimum Swift Version**: Swift 6.0+

### Enforcement

- PR reviewers verify constitutional alignment
- CI pipeline enforces MUST-level (blocking), SHOULD-level (warnings)
- Three-tier enforcement:
  - **MUST**: Blocks merge
  - **SHOULD**: Warning, requires override justification
  - **MAY**: Informational only

---

## Version History

**Version**: 1.0.0
**Ratified**: 2025-12-05
**Last Amended**: 2025-12-05

**Changelog**:
- **1.0.0** (2025-12-05): Initial constitution with 8 core principles, three-tier enforcement, BDFL governance, tiered platform support, tiered RPC coverage model.
