# Phase 8: RPC Server & Privacy

**Goal**: Expose `BitcoinKernel` as a JSON-RPC server compatible with Bitcoin Core's RPC interface, and add privacy-preserving transaction features — completing the "kernel as full node replacement" vision.

**Status**: FUTURE  
**Last Updated**: 2026-05-07

---

## Goal

Enable external tools (wallets, CLN, block explorers, debugging utilities) to query `BitcoinKernel` through a standard Bitcoin Core-compatible JSON-RPC server — the same interface that `bitcoind` exposes. This removes the last architectural gap between "kernel as node layer" and "kernel as full node."

Additionally, add privacy-preserving transaction features (Ricochet multi-hop sends, STONEWALL entropy mixing) that make `BitcoinKernel`-backed wallets competitive with privacy-focused wallets like Samourai.

---

## Key Features

### 8.1 JSON-RPC Server

**Purpose & User Value**: Provide a Bitcoin Core-compatible JSON-RPC server that exposes `BitcoinKernel`'s capabilities — block data, chain info, mempool queries, fee estimation, and transaction broadcast — over HTTP or Unix socket. This enables drop-in replacement of `bitcoind` for any tool that speaks Bitcoin Core RPC.

**Success Metrics**:
- `KernelRPCServer` type: configurable HTTP server (localhost by default)
- Exposes the same RPC methods as `bitcoind` (subset sufficient for wallets/CLN):
  - `getblockchaininfo` — chain name, headers, blocks, IBD status
  - `getblockhash <height>` — block hash at height
  - `getblock <hash> <verbosity>` — block data (raw hex, JSON, or JSON+tx)
  - `getbestblockhash` — best block hash
  - `getblockcount` — current block height
  - `getrawmempool` — mempool txids
  - `getmempoolinfo` — mempool statistics
  - `estimatesmartfee <blocks>` — fee estimation
  - `sendrawtransaction <hex>` — transaction broadcast
  - `gettxout <txid> <vout>` — UTXO lookup
  - `getpeerinfo` — connected P2P peers
  - `getnetworkinfo` — network statistics
- Authentication: cookie file or user/password (matching Bitcoin Core)
- Configurable: port, bind address, TLS (optional)
- Thread-safe — serves concurrent requests
- Compatible with `bitcoin-cli` as client

**Dependencies**: Phase 4 (P2P BlockSource + tx broadcast), Phase 6 (mempool sync), Phase 7 (UTXO lookup API)

**Reference**: Yuki's `src/rpc/` module (minimal Bitcoin Core-compatible RPC server), Bitcoin Core's `src/rpc/` for method signatures

---

### 8.2 Ricochet — Multi-Hop Transaction Sends

**Purpose & User Value**: Send transactions through multiple hops (your own wallets) to obscure the origin of funds — making chain analysis significantly harder. Each hop adds a time delay and a new transaction.

**Success Metrics**:
- `RicochetSender` type: configurable hop count (default: 4), delay between hops
- Each hop: create a new transaction sending to the next hop's address
- Uses different fee rates per hop (staggered, looks natural)
- Hops use different addresses (HD wallet derivation, different paths)
- Final hop sends to the intended recipient
- All hops broadcast via `TransactionBroadcaster` (Phase 4)
- Configurable: hop count, delay, fee strategy, address derivation

**Dependencies**: Phase 4 (tx broadcast), Phase 7 (UTXO lookup for change detection)

**Reference**: Samourai Wallet's Ricochet implementation

---

### 8.3 STONEWALL — Entropy-Enhanced Transactions

**Purpose & User Value**: Create transactions that look like CoinJoin by adding entropy — multiple inputs, multiple outputs, with the real payment hidden among decoy outputs. Makes chain analysis ambiguous about which output is the real payment.

**Success Metrics**:
- `StonewallBuilder` type: constructs transactions with entropy
- Multiple inputs: real UTXO + decoy UTXOs (from same wallet, different paths)
- Multiple outputs: real payment + decoy change outputs
- Decoy outputs go back to the same wallet (different addresses)
- Transaction structure indistinguishable from CoinJoin
- Fee calculation accounts for extra inputs/outputs
- Configurable: number of decoy inputs/outputs, entropy source

**Dependencies**: Phase 4 (tx broadcast), Phase 7 (UTXO lookup for input selection)

**Reference**: Samourai Wallet's STONEWALL implementation

---

### 8.4 Stowaway — PayJoin (BIP 78)

**Purpose & User Value**: Implement BIP 78 (PayJoin / P2EP) — the sender and receiver collaborate to create a transaction where both contribute inputs, making it impossible to determine which inputs belong to which party and which outputs are payment vs change.

**Success Metrics**:
- `PayjoinClient` type: BIP 78-compliant client
- Sender flow: `sendPayjoin(psbt:to:)` — initiates PayJoin with receiver's endpoint
- Receiver flow: `receivePayjoin(proposal:) -> PSBT` — contributes inputs, returns signed PSBT
- Uses PSBT v0 or v2 (BIP 174 / BIP 370)
- HTTPS endpoint for receiver (configurable)
- Falls back to regular send if receiver doesn't support PayJoin
- Tested against BIP 78 test vectors

**Dependencies**: Phase 4 (tx broadcast), Phase 7 (UTXO lookup)

**Reference**: BIP 78 specification, Samourai Wallet's Stowaway implementation

---

### 8.5 BIP 47 — Reusable Payment Codes (PayNym)

**Purpose & User Value**: Implement BIP 47 reusable payment codes — a privacy-preserving way to receive payments without address reuse. Sender derives unique addresses from the receiver's payment code using ECDH, without any on-chain link between the payment code and the derived addresses.

**Success Metrics**:
- `PaymentCode` type: BIP 47 payment code encoding/decoding
- `deriveAddress(from:index:)` — derive a unique receiving address from a payment code
- Notification transaction: sender creates and broadcasts a notification tx (OP_RETURN)
- Address derivation: ECDH shared secret + HMAC-SHA512 → child keys
- Supports BIP 47 v1 and v2 (SegWit)
- Payment code exchange: via URI scheme, QR code, or manual entry
- Works with HD wallets (BIP 32)

**Dependencies**: Phase 4 (tx broadcast for notification tx), Phase 7 (UTXO lookup for scanning)

**Reference**: BIP 47 specification, Samourai Wallet's PayNym implementation

---

## Phase Dependencies & Sequencing

```
Phase 4 (P2P Networking: BlockSource + tx broadcast)
    └── Phase 6 (Advanced P2P: mempool sync)
            └── Phase 7 (Lightning Integration: UTXO lookup)
                    └── Phase 8 (RPC Server & Privacy)
                            ├── 8.1 JSON-RPC Server (foundation for everything)
                            ├── 8.2 Ricochet (independent)
                            ├── 8.3 STONEWALL (independent)
                            ├── 8.4 Stowaway / PayJoin (independent)
                            └── 8.5 BIP 47 Payment Codes (independent)
```

8.1 is the foundation. 8.2-8.5 are independent privacy features that can be developed in any order.

---

## Phase-Level Metrics & Success Criteria

| Metric | Target |
|--------|--------|
| Build success | All Tier 1 platforms (macOS, iOS) |
| RPC server compatibility | `bitcoin-cli getblockchaininfo` returns valid response |
| RPC method coverage | ≥12 methods (subset sufficient for wallets/CLN) |
| Ricochet hop success rate | 100% on signet with 4 hops |
| STONEWALL entropy | ≥2 decoy inputs + ≥2 decoy outputs |
| PayJoin compatibility | BIP 78 test vectors pass |
| BIP 47 address derivation | Matches reference implementation |
| Documentation | RPC method docs, privacy feature guides |

---

## Risks & Assumptions

| Risk | Mitigation |
|------|------------|
| JSON-RPC server security (exposing kernel to network) | Bind to localhost by default; authentication required; TLS optional |
| Ricochet/staggered sends increase fees significantly | Configurable hop count; document cost trade-offs |
| PayJoin requires receiver cooperation | Graceful fallback to regular send |
| BIP 47 notification transaction is visible on-chain | Document privacy model; notification tx is one-time per payment code pair |
| Privacy features add complexity to kernel API | Keep privacy features as separate modules; opt-in only |

**Assumptions**:
- Phase 6 mempool sync provides sufficient data for fee estimation and UTXO selection
- JSON-RPC server uses Foundation's `NWListener` or `swift-nio` (constitutional amendment may be needed for nio)
- Privacy features are opt-in — kernel remains usable without them
- BIP 47, BIP 78 are stable specifications

---

## BIP Coverage

| BIP | Name | Priority | Notes |
|-----|------|----------|-------|
| 47 | Reusable Payment Codes | SHOULD | Privacy-preserving address derivation |
| 78 | PayJoin / P2EP | SHOULD | Collaborative transactions |

---

## Phase Notes / Change Log

- 2026-05-07: Initial creation. Based on gap analysis from delvingbitcoin.org cross-reference and remaining repo exploration. Addresses the JSON-RPC server gap (Bitcoin Core-compatible, reference Yuki's implementation) and privacy feature gap (Ricochet/STONEWALL per Samourai patterns, BIP 47 payment codes, BIP 78 PayJoin).