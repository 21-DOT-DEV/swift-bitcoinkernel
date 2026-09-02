# Phase 2: Daemon API

**Goal**: Create a Swift-native `Daemon` abstraction for controlling the embedded Bitcoin Core node lifecycle with proper state management, a type-safe configuration builder, and callback-based progress tracking.

**Status**: COMPLETE  
**Last Updated**: 2026-05-07

---

## Goal

Provide a clean Swift API for launching, bootstrapping, configuring, and shutting down an embedded `bitcoind` process. The daemon runs on a dedicated thread and communicates via JSON-RPC (HTTP or in-process direct bridge).

---

## Key Features

### 2.1 Node Interface Wrapper

**Purpose & User Value**: Wrap Bitcoin Core's C++ entry point (`bitcoind_main`) to provide safe Swift access to node lifecycle — launch on a background thread, register the RPC bridge, and handle SOCKS5 reset for in-process restarts.

**Success Metrics**:
- `Daemon.start(_ arguments: [String])` launches bitcoind on a detached thread
- `bitcoin_rpc_register()` called before RPC server starts
- `bitcoin_socks_reset()` clears sticky interrupt flag for in-process restarts
- Thread-safe via `Mutex` guard against duplicate `start()` calls
- `Daemon.waitUntilStopped()` blocks until `bitcoind_main()` returns

**Dependencies**: Phase 1 complete

**Status**: COMPLETE (`Sources/Bitcoin/Daemon.swift`)

---

### 2.2 Daemon Lifecycle API

**Purpose & User Value**: Provide a high-level `Daemon` type that manages startup, bootstrap (RPC bridge activation), and shutdown with a clean Swift API.

**Success Metrics**:
- `Daemon.start(_ arguments:)` — launches daemon, returns immediately
- `Daemon.bootstrap(url:username:password:)` — polls RPC readiness, activates direct bridge (explicit credentials)
- `Daemon.bootstrap(cookieFile:port:)` — cookie-based auth (credential-free)
- `Daemon.waitUntilStopped()` — blocks until daemon shutdown completes
- Direct RPC bridge via hidden `_bridge_init` RPC (in-process, zero-latency)
- Exponential backoff polling with configurable timeout

**Dependencies**: 2.1 Node Interface Wrapper

**Status**: COMPLETE (`Sources/Bitcoin/Daemon.swift`)

---

### 2.3 Configuration Builder

**Purpose & User Value**: Provide a type-safe configuration builder (`BitcoinConfig`) with phantom types for network scoping, replacing raw string arguments and reducing errors.

**Success Metrics**:
- `BitcoinConfig` struct with 12 extension files covering:
  - Core (datadir, network, debug)
  - Network (proxy, listen, maxconnections, Tor SOCKS5)
  - RPC (rpcport, rpcuser, rpcpassword, rpccookiefile)
  - Wallet (wallet, walletdir, disablewallet)
  - Mining, Validation, ZMQ, Relay, Debug
  - Presets (regtest, testnet, signet, mainnet)
  - Raw argument passthrough for advanced users
- Phantom-typed network scoping (`BitcoinConfig+NetworkScoped.swift`)
- Value types: `Satoshis`, `BTCAmount`, `Network`, `HostPort`, `ZMQEndpoint`

**Dependencies**: 2.2 Daemon Lifecycle API

**Status**: COMPLETE (`Sources/Bitcoin/Config/`)

---

## Phase Dependencies & Sequencing

```
2.1 Node Interface Wrapper ✅
    └── 2.2 Daemon Lifecycle API ✅
            └── 2.3 Configuration Builder ✅
```

---

## Phase-Level Metrics

| Metric | Target | Result |
|--------|--------|--------|
| Build success | All Tier 1 platforms | ✅ |
| Test coverage | ≥80% of Daemon API | ✅ |
| Documentation | All public types documented | ✅ |
| Example app | NodeApp demonstrates full lifecycle | ✅ |

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Global state in Bitcoin Core | Document singleton constraints; Mutex guard |
| Thread safety issues | Mutex + DispatchSemaphore; SOCKS5 reset on restart |
| Cookie file race condition | Exponential backoff polling with timeout |

---

## Phase Notes / Change Log

- 2026-05-07: Marked COMPLETE. `Daemon.swift` (227 lines) with start/bootstrap/waitUntilStopped. `BitcoinConfig` with 12 extensions. `NodeApp` example demonstrates full lifecycle.
- 2025-12-05: Initial creation.