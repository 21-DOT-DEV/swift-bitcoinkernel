# Phase 2: Daemon API

**Goal**: Create a Swift-native `Daemon` abstraction for controlling the embedded Bitcoin Core node lifecycle with proper state management and callbacks.

**Status**: 🔜 Planned  
**Last Updated**: 2025-12-05

---

## Features

### 2.1 Node Interface Wrapper

**Purpose & User Value**: Wrap Bitcoin Core's `interfaces::Node` C++ class to provide safe Swift access to node lifecycle methods.

**Success Metrics**:
- Swift wrapper for `interfaces::Node` created
- Safe memory management at C++/Swift boundary
- `appInitMain()`, `startShutdown()`, `appShutdown()` exposed
- `shutdownRequested()` exposed for polling
- No memory leaks detected in tests

**Dependencies**: Phase 1 complete

**Notes**:
- Use Swift's C++ interop (`interoperabilityMode(.Cxx)`)
- Document ownership semantics
- Catch C++ exceptions and convert to Swift errors

---

### 2.2 Daemon Lifecycle API

**Purpose & User Value**: Provide a high-level `Daemon` type that manages node startup, shutdown, and state transitions with a clean Swift API.

**Success Metrics**:
- `Daemon` type created with:
  - `static func start(_ arguments: [String]) async throws`
  - `static func stop() async throws`
  - `static var state: DaemonState { get }`
- `DaemonState` enum: `.uninitialized`, `.initializing`, `.syncing`, `.ready`, `.shuttingDown`
- State transitions are thread-safe
- Graceful shutdown flushes data

**Dependencies**: 2.1 Node Interface Wrapper

**Notes**:
- Consider whether Daemon should be a singleton or support instances
- Initial implementation can be simpler; expand as needed

---

### 2.3 Sync Progress & State Callbacks

**Purpose & User Value**: Expose sync progress and state change notifications via AsyncSequence so apps can show loading indicators and react to node state.

**Success Metrics**:
- `Daemon.syncProgress: AsyncStream<Double>` (0.0...1.0)
- `Daemon.blockTips: AsyncStream<BlockTip>` (new blocks)
- `Daemon.stateChanges: AsyncStream<DaemonState>`
- Callbacks wired to `interfaces::Node` handlers:
  - `handleNotifyBlockTip`
  - `handleShowProgress`
- Progress updates during IBD

**Dependencies**: 2.2 Daemon Lifecycle API

**Notes**:
- Use `AsyncStream` with continuation for bridging C++ callbacks
- Consider backpressure handling for high-frequency updates

---

### 2.4 Configuration Builder

**Purpose & User Value**: Provide a type-safe configuration builder instead of raw string arguments, reducing errors and improving discoverability.

**Success Metrics**:
- `DaemonConfiguration` struct with typed properties:
  - `network: Network` (.mainnet, .testnet, .regtest, .signet)
  - `dataDirectory: URL`
  - `rpcPort: UInt16`
  - `rpcCredentials: RPCCredentials?`
  - `pruneMode: PruneMode` (.disabled, .manual, .automatic(blocks:))
  - `blockFilterIndex: Bool`
- `func toArguments() -> [String]` for conversion
- Documentation with examples

**Dependencies**: 2.2 Daemon Lifecycle API

**Notes**:
- Start with common options; expand based on user needs
- Raw arguments still available for advanced users

---

## Phase Dependencies & Sequencing

```
2.1 Node Interface Wrapper
    └── 2.2 Daemon Lifecycle API
            ├── 2.3 Sync Progress & State Callbacks
            └── 2.4 Configuration Builder
```

---

## Phase-Level Metrics

| Metric | Target |
|--------|--------|
| Build success | All Tier 1 platforms |
| Test coverage | ≥80% of Daemon API |
| Sync time (regtest) | Baseline established |
| Documentation | All public types documented |

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| C++ callback bridging complexity | Prototype with simple callback first |
| Global state in Bitcoin Core | Document singleton constraints |
| Thread safety issues | Use actors or explicit synchronization |
