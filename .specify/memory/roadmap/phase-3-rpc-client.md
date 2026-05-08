# Phase 3: RPC Client + Wallet RPC

**Goal**: Create a type-safe RPC client protocol with pluggable transports (direct, HTTP, cookie, auto-detection) and comprehensive typed wrappers for all Bitcoin Core RPC methods, including wallet.

**Status**: COMPLETE  
**Last Updated**: 2026-05-07

---

## Goal

Provide a complete, type-safe Swift RPC client covering all Bitcoin Core v31.x RPC methods. The transport abstraction enables in-process (zero-latency), HTTP, cookie-based, and auto-detecting connections. Wallet functionality is exposed exclusively through RPC — `BitcoinKernel` is a node layer, not a wallet.

> **Architecture note**: Old Phase 4 (Wallet Support) from roadmap v1.0.0 is absorbed here. Wallet operations are RPC-only. There is no separate Swift wallet library. Wallets and SDKs (BDK, LDK, fltrWallet) consume `BitcoinKernel` as their node layer for block delivery and transaction broadcast.

---

## Key Features

### 3.1 RPCTransport Protocol & Implementations

**Purpose & User Value**: Define a pluggable transport abstraction that decouples RPC method definitions from the underlying connection mechanism, enabling in-process, HTTP, and cookie-based connections interchangeably.

**Success Metrics**:
- `RPCTransport` protocol defined with `send(_:)` method
- `DirectTransport` — in-process C bridge via `bitcoin_rpc()` (zero-latency)
- `HTTPTransport` — HTTP/HTTPS with Basic authentication
- `CookieTransport` — reads `.cookie` file for credential-free auth
- `AutoTransport` — auto-detects best transport per call (direct for non-wallet, HTTP for wallet)
- `JSONRPCService` — request/response envelope handling

**Dependencies**: Phase 2 complete (Daemon must be running for DirectTransport)

**Status**: COMPLETE (`Sources/Bitcoin/RPC/JSONRPC/`)

---

### 3.2 RPCClient — Typed Methods (171 total)

**Purpose & User Value**: Provide fully-typed Swift wrappers for all Bitcoin Core RPC methods, eliminating string-based JSON manipulation and enabling compile-time safety.

**Success Metrics**:
- 171 typed methods across 8 categories:
  - Blockchain (51) — blocks, headers, mempool, UTXO, chainstate, proofs, filters
  - Wallet (55) — balance, send, PSBT, descriptors, encryption, labels, transactions
  - Raw Transactions (21) — create, sign, send, decode, PSBT lifecycle, mempool acceptance
  - Network (19) — peers, banning, ZMQ, addrman, connection counts
  - Util (9) — fee estimation, address validation, descriptor parsing
  - Mining (7) — block templates, hashrate, priority, submission
  - Control (6) — memory, RPC info, logging, stop, uptime
  - Generating (3) — generate to address/descriptor/block
- All response types are `Codable`, `Sendable`, and documented
- Generic `send<T>(_ method:params:)` for untyped passthrough

**Dependencies**: 3.1 RPCTransport Protocol

**Status**: COMPLETE (`Sources/Bitcoin/RPC/RPCClient*.swift`)

---

### 3.3 RPCModels — Response Types (95 models)

**Purpose & User Value**: Provide strongly-typed, Codable model types for all RPC responses, with satoshi-precision arithmetic and proper timestamp handling.

**Success Metrics**:
- 95 Codable model types covering all RPC response schemas
- `BTCAmount` — satoshi-precision arithmetic (Int64 sats, Decimal BTC)
- `UnixTimestamp` — epoch seconds with `Date` conversion
- `RPCError` — server-originated JSON-RPC errors
- `BlockFilter` — compact block filter data from `getblockfilter`
- `LastProcessedBlock` — block hash + height from wallet RPCs
- 177 decode tests with Bitcoin Core test vectors

**Dependencies**: None (pure models)

**Status**: COMPLETE (`Sources/RPCModels/`)

---

### 3.4 Wallet RPC Coverage

**Purpose & User Value**: Expose all Bitcoin Core wallet functionality through typed RPC methods. This is the full extent of wallet support — there is no separate Swift wallet API.

**Success Metrics**:
- 55 typed wallet RPC methods: `getBalance`, `getBalances`, `listWallets`, `createWallet`, `loadWallet`, `unloadWallet`, `getNewAddress`, `sendToAddress`, `listTransactions`, `listUnspent`, `createRawTransaction`, `signRawTransactionWithWallet`, `sendRawTransaction`, `listDescriptors`, `importDescriptors`, `walletCreateFundedPSBT`, `walletProcessPSBT`, `finalizePSBT`, `bumpFee`, `abandonTransaction`, `backupWallet`, `encryptWallet`, `walletPassphrase`, etc.
- `BTCAmount` used for all satoshi-denominated values
- `LastProcessedBlock` returned for scanprogress-aware methods

**Dependencies**: 3.1 RPCTransport Protocol

**Status**: COMPLETE (`Sources/Bitcoin/RPC/RPCClient+Wallet.swift`)

---

## Phase Dependencies & Sequencing

```
3.1 RPCTransport Protocol ✅
    └── 3.2 RPCClient (171 methods) ✅
            ├── 3.3 RPCModels (95 types) ✅
            └── 3.4 Wallet RPC Coverage ✅
```

---

## Phase-Level Metrics

| Metric | Target | Result |
|--------|--------|--------|
| Build success | All Tier 1 platforms | ✅ |
| Test coverage | ≥80% of RPC client API | ✅ |
| RPC coverage | 171 typed methods | ✅ |
| RPC models | 95 Codable types | ✅ |
| Model decode tests | 177 tests with Bitcoin Core vectors | ✅ |
| Documentation | All public types documented (DocC) | ✅ |
| Example apps | NodeApp (daemon + RPC browser), KernelApp (kernel sync) | ✅ |

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Response types drift from Bitcoin Core | 177 decode tests against upstream vectors; CI catches regressions |
| Error code mapping incomplete | `RPCError` captures server-originated errors; transport errors surfaced distinctly |
| Wallet methods require running daemon | Documented; `AutoTransport` routes wallet RPCs over HTTP transparently |

---

## Phase Notes / Change Log

- 2026-05-07: Marked COMPLETE. Absorbed old Phase 4 (Wallet Support) — wallet is RPC-only, `BitcoinKernel` is node layer. 171 typed RPC methods, 95 Codable models, 5 transport types, 177 decode tests. NodeApp and KernelApp examples operational.
- 2025-12-05: Initial creation (as Phase 3: RPC Client).