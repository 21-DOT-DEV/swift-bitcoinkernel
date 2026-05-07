# Phase 4: P2P Networking

**Goal**: Build a Swift-native P2P networking layer atop `swift-event` (libevent) that implements the Bitcoin wire protocol, delivers a `BlockSource` conformer for `BlockchainSync`, and provides transaction broadcast — all with BIP 324 v2 encrypted transport.

**Status**: NEXT UP  
**Last Updated**: 2026-05-07

---

## Goal

Enable `BitcoinKernel` to fetch blocks and broadcast transactions directly from the Bitcoin P2P network — no HTTP, no Esplora, no Rust FFI. This makes `BitcoinKernel` a self-contained node layer that any wallet SDK can consume. The existing `BlockSource` protocol is the integration point: a `P2PBlockSource` conformer drops into `BlockchainSync` identically to `EsploraBlockSource`.

---

## Key Features

### 4.1 P2P Wire Protocol

**Purpose & User Value**: Implement the core Bitcoin P2P message framing, handshake, and essential message types in pure Swift, enabling direct peer connections via `swift-event` TCP sockets.

**Success Metrics**:
- Message framing: magic bytes, command, length, checksum, payload
- Handshake: `version` / `verack` exchange with protocol version ≥ 70016
- Keepalive: `ping` / `pong` with configurable interval
- Header sync: `getheaders` / `headers` messages
- Block fetch: `getdata` (MSG_BLOCK, MSG_HEADER) / `block` messages
- Protocol negotiation: `sendheaders` (BIP 130), `feefilter` (BIP 133), `sendcmpct` (BIP 152, low-bandwidth mode)
- Transaction broadcast: `inv` (MSG_WTX) / `getdata` / `tx` messages (BIP 339 WTXID relay)
- All message types are `Sendable` and documented

**Dependencies**: Phase 3 complete (`BlockSource` protocol stable)

**Reference implementations**: Kyoto's `network/` module, Floresta's `floresta-wire` crate, SwiftSync's `bitcoin-p2p` usage

---

### 4.2 BIP 324 — v2 Encrypted Transport

**Purpose & User Value**: Implement BIP 324 v2 P2P encrypted transport as a hard requirement — all peer connections use the v2 protocol from the first release.

**Success Metrics**:
- ElligatorSwift key exchange (using `secp256k1` ellswift module, already compiled in)
- ChaCha20-Poly1305 AEAD for message encryption/decryption
- V2 transport handshake: garbage terminator, version negotiation, application data transition
- V2 message framing: encrypted length prefix, ciphertext, authentication tag
- Backward compatibility: detect v1 peers, fall back gracefully (optional)
- Test vectors from BIP 324 pass

**Dependencies**: 4.1 P2P Wire Protocol (v2 transport wraps v1 messages)

**Reference**: Floresta's BIP 324 implementation, Bitcoin Core's `src/net_v2transport.cpp`

---

### 4.3 Peer Connection Management

**Purpose & User Value**: Manage peer lifecycle — DNS bootstrapping, connection establishment, health monitoring, and graceful disconnection — with configurable peer count and reconnection policy.

**Success Metrics**:
- DNS seed bootstrapping (query DNS seeds for initial peer addresses)
- TCP connection via `swift-event` async sockets
- Configurable target peer count (default: 3)
- Connection health: `ping`/`pong` keepalive, timeout detection
- Automatic reconnection with exponential backoff and jitter
- Peer scoring: track latency, block delivery speed, uptime
- Graceful disconnect: send `version` with zero services, close socket

**Dependencies**: 4.1 P2P Wire Protocol, 4.2 BIP 324

**Reference**: SwiftSync's multi-threaded peer management, Kyoto's AddrMan-inspired bucket system

---

### 4.4 P2PBlockSource — BlockSource Conformer

**Purpose & User Value**: Implement the `BlockSource` protocol using P2P peers, enabling `BlockchainSync` to fetch and validate blocks directly from the Bitcoin network — a drop-in replacement for `EsploraBlockSource`.

**Success Metrics**:
- `P2PBlockSource` conforms to `BlockSource`:
  - `bestTip()` — returns the highest header known to connected peers
  - `blockHash(atHeight:)` — returns hash at height from header chain
  - `blockHeader(for:)` — fetches header via `getdata` (MSG_HEADER)
  - `block(for:)` — fetches full block via `getdata` (MSG_BLOCK)
- Works identically with `BlockchainSync` engine (no app-layer changes)
- Handles peer churn during sync (blocks may come from different peers)
- `Foundation.Progress` integration (same as `EsploraBlockSource`)

**Dependencies**: 4.1 P2P Wire Protocol, 4.3 Peer Connection Management

---

### 4.5 Transaction Broadcast

**Purpose & User Value**: Provide a Swift API for broadcasting transactions to P2P peers, enabling wallets to send through `BitcoinKernel` without needing a separate broadcast mechanism.

**Success Metrics**:
- `TransactionBroadcaster` protocol or method on P2P client:
  - `broadcast(_ transaction: Transaction) async throws`
- Uses `inv` (MSG_WTX per BIP 339) → `getdata` → `tx` flow
- Broadcasts to multiple peers for reliability
- Returns when at least one peer acknowledges
- Fee-aware: respects `feefilter` (BIP 133) thresholds from peers

**Dependencies**: 4.1 P2P Wire Protocol, 4.3 Peer Connection Management

---

### 4.6 P2P Example App

**Purpose & User Value**: Demonstrate P2P-based `BitcoinKernel` sync in a working example app, showing the transition from Esplora-based to P2P-based block delivery.

**Success Metrics**:
- Example app: P2PBlockSource with BlockchainSync on signet
- Peer connection status UI (connected peers, latency)
- Sync progress UI (reuses existing `BlockchainSync.Update` patterns)
- Tor integration (route P2P through SOCKS5 proxy, reusing existing Tor infrastructure)
- Tests: `P2PBlockSourceTests`, `WireProtocolTests`, `BIP324TransportTests`

**Dependencies**: 4.4 P2PBlockSource, 4.5 Transaction Broadcast

---

## Phase Dependencies & Sequencing

```
4.1 P2P Wire Protocol
    ├── 4.2 BIP 324 v2 Transport (parallel: wraps v1 messages)
    └── 4.3 Peer Connection Management (parallel: uses wire protocol)
            └── 4.4 P2PBlockSource
                    └── 4.5 Transaction Broadcast (parallel: independent feature)
                            └── 4.6 P2P Example App
```

4.1 is the critical path. 4.2 and 4.3 can be developed in parallel once basic message framing works.

---

## Phase-Level Metrics & Success Criteria

| Metric | Target |
|--------|--------|
| Build success | All Tier 1 platforms (macOS, iOS) |
| Test coverage | ≥80% of P2P API surface |
| BIP 324 test vectors | All pass |
| P2P Block Throughput (signet) | Baseline established (blocks/sec) |
| Tx Broadcast Latency | Baseline established (time to first peer relay) |
| Peer connection reliability | ≥95% uptime on signet with 3 peers |
| Documentation | All public types documented (DocC) |
| Example app | P2P sync demo on signet |

---

## Risks & Assumptions

| Risk | Mitigation |
|------|------------|
| P2P wire protocol complexity (100+ message types) | Phase delivery: only the 10 message types needed for block fetch + tx broadcast; defer rest to Phase 6 |
| BIP 324 implementation difficulty | Leverage Floresta's Rust implementation for protocol logic reference; use `secp256k1` ellswift module already compiled in |
| iOS background socket limitations | Focus macOS first; iOS with `BGTaskScheduler` for background refresh; document limitations |
| DNS seed availability / reliability | Hardcoded fallback addresses; user-configurable peer list |
| Peer churn during IBD | `BlockchainSync` is hash-addressed — blocks can come from any peer; peer scoring prioritizes fast peers |
| `swift-event` async I/O adequacy | Already proven in `bitcoind`'s HTTP server and event loop; TCP client sockets are the same primitives |

**Assumptions**:
- `swift-event` (libevent) provides sufficient async TCP socket primitives for P2P
- Signet is the primary real-network test target; mainnet IBD is documented as impractical for mobile
- DNS seeds are reachable from macOS/iOS without additional network configuration
- Existing `secp256k1` ellswift module (compiled with `ENABLE_MODULE_ELLSWIFT`) works for BIP 324 key exchange

---

## BIP Coverage

| BIP | Name | Priority | Notes |
|-----|------|----------|-------|
| 130 | sendheaders | MUST | Header-first block announcements |
| 133 | feefilter | MUST | Fee-based tx filtering for broadcast |
| 152 | Compact Block Relay | SHOULD | Low-bandwidth mode for bandwidth savings (nice-to-have) |
| 324 | v2 P2P Encrypted Transport | MUST | Hard requirement from first release |
| 339 | WTXID relay | MUST | Modern tx announcement format |

---

## Phase Notes / Change Log

- 2026-05-07: Initial creation. Replaces old Phase 5 (Network Client) from roadmap v1.0.0. Scoped to blocks + tx broadcast per BIP 324, BIP 130, BIP 133, BIP 339. Mempool sync and addr gossip deferred to Phase 6. BIP 324 v2 transport is a hard requirement. Pure Swift, no Rust FFI. Reference implementations: Kyoto, Floresta, SwiftSync (for wire protocol patterns only).