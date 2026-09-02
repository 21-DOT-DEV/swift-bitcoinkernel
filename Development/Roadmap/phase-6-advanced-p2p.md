# Phase 6: Advanced P2P

**Goal**: Extend the P2P networking layer with mempool synchronization, address gossip, peer discovery, and connection pooling — completing the "all-in on P2P" vision while remaining pure Swift.

**Status**: FUTURE  
**Last Updated**: 2026-05-07

---

## Goal

Complete the P2P networking story: enable `BitcoinKernel` to maintain a local mempool view via P2P gossip, discover new peers through address exchange, and manage connections efficiently. These features are deferred because blocks + tx broadcast (Phase 4) and compact filters (Phase 5) provide the core node-layer functionality that wallets need first.

---

## Key Features

### 6.1 Mempool Synchronization

**Purpose & User Value**: Maintain a local mempool view by receiving transaction announcements (`inv` messages) from P2P peers, enabling fee estimation, transaction tracking, and mempool-aware wallet operations without relying on Esplora or bitcoind RPC.

**Success Metrics**:
- `Mempool` type: thread-safe, observable transaction set
- Receives `inv` (MSG_WTX) announcements from connected peers
- Fetches unknown transactions via `getdata` (MSG_WTX per BIP 339)
- Respects `feefilter` (BIP 133) — peers only relay transactions above minimum fee
- Prunes expired/replaced transactions
- Exposes `transactions: AsyncStream<Transaction>` for reactive consumers
- Mempool size and fee distribution queryable

**Dependencies**: Phase 4 (P2P wire protocol, peer connections)

**Reference**: Floresta's `floresta-mempool` crate, Bitcoin Core's `CTxMemPool`

---

### 6.2 Address Gossip & Peer Discovery

**Purpose & User Value**: Discover new peers through P2P address gossip (`addr`/`addrv2` messages per BIP 155), replacing DNS bootstrapping as the primary peer discovery mechanism for long-running nodes.

**Success Metrics**:
- `PeerDiscovery` type: maintains address database
- Receives `addr` (v1) and `addrv2` (BIP 155) messages from peers
- Supports all BIP 155 network types: IPv4, IPv6, Tor v3, I2P, Cjdns
- Address freshness tracking (last seen timestamp)
- Address bucketing (new/tried tables, per Bitcoin Core's AddrMan)
- `getaddr` message support for requesting peer addresses
- Persists address database across restarts (optional)
- Tor v3 address support (32-byte addresses via `addrv2`)

**Dependencies**: Phase 4 (P2P wire protocol)

**Reference**: Kyoto's AddrMan-inspired bucket system, Floresta's `peers.json`, Bitcoin Core's `CAddrMan`

---

### 6.3 Connection Pooling & Multi-Peer Management

**Purpose & User Value**: Manage a pool of peer connections with intelligent peer selection, load balancing, and failover — enabling reliable P2P operation at scale.

**Success Metrics**:
- `PeerPool` type: manages N peer connections (configurable)
- Intelligent peer selection for block requests (fastest peer first)
- Load balancing for transaction broadcast (random subset)
- Connection diversity: avoid multiple connections to same /16 subnet
- Automatic failover: replace failed peers from address database
- Connection limits per network type (respect `maxconnections`)
- Peer banning for protocol violations (temporary/permanent)
- Metrics: connection uptime, block delivery latency per peer

**Dependencies**: 6.1 Mempool Synchronization, 6.2 Address Gossip

---

### 6.4 Compact Block Relay (BIP 152)

**Purpose & User Value**: Implement BIP 152 Compact Block Relay (high-bandwidth mode) for bandwidth-efficient block propagation — blocks are announced with short transaction IDs, and peers reconstruct from their mempool.

**Success Metrics**:
- `sendcmpct` message negotiation (high-bandwidth mode for selected peers)
- `cmpctblock` message parsing (HeaderAndShortIDs)
- Block reconstruction from mempool (resolve short IDs to full transactions)
- `getblocktxn` / `blocktxn` for missing transactions
- Short transaction ID computation (SipHash-2-4)
- Version 2 support (SegWit-aware short IDs)
- Bandwidth savings measured: compact block size vs full block size

**Dependencies**: 6.1 Mempool Synchronization (mempool needed for reconstruction)

**Note**: This was noted as nice-to-have in Phase 4. It's promoted here because mempool sync (6.1) is a prerequisite for compact block reconstruction.

---

### 6.5 Erlay — Transaction Relay Efficiency (BIP 330)

**Purpose & User Value**: Optionally implement BIP 330 (Erlay) transaction announcement reconciliation using PinSketch set reconciliation — reducing transaction relay bandwidth by ~40%.

**Success Metrics**:
- `sendtxrcncl` message for protocol negotiation
- `reqrecon` / `sketch` / `reqsketchext` / `reconcildiff` messages
- PinSketch-based set reconciliation (GF(2^32) finite field arithmetic)
- Reconciliation salt exchange and short ID computation
- Bandwidth reduction measured: reconciliation vs full INV flooding

**Dependencies**: 6.1 Mempool Synchronization, 6.3 Connection Pooling

**Risk**: BIP 330 is still Draft status — implementation should be gated behind a feature flag until finalized. Monitor `delvingbitcoin.org` for Erlay adoption progress.

---

## Phase Dependencies & Sequencing

```
6.1 Mempool Synchronization
    └── 6.4 Compact Block Relay (BIP 152, needs mempool)
    
6.2 Address Gossip & Peer Discovery (independent)
    └── 6.3 Connection Pooling (needs address DB for failover)
            └── 6.5 Erlay (BIP 330, needs connection pool)
```

6.1 and 6.2 are independent — both extend the Phase 4 wire protocol with new message types. 6.3 depends on 6.2 for peer selection. 6.4 depends on 6.1 for mempool reconstruction. 6.5 is optional and gated behind BIP 330 finalization.

---

## Phase-Level Metrics & Success Criteria

| Metric | Target |
|--------|--------|
| Build success | All Tier 1 platforms (macOS, iOS) |
| Mempool sync latency | Baseline established (time from tx broadcast to local mempool entry) |
| Address database size | Baseline established (# addresses discovered) |
| Peer pool uptime | ≥99% with 8+ peers on signet |
| Compact block bandwidth savings | ≥50% vs full block download |
| Erlay bandwidth savings (if implemented) | ≥30% vs full INV flooding |
| Documentation | All public types documented (DocC) |

---

## Risks & Assumptions

| Risk | Mitigation |
|------|------------|
| BIP 330 (Erlay) still Draft — implementation wasted if spec changes | Feature-gate behind compile flag; monitor BIP status on delvingbitcoin.org |
| Mempool sync bandwidth (hundreds of tx/sec on mainnet) | Not targeting mainnet mobile; signet/testnet for validation; mainnet for server-side only |
| Address database poisoning (malicious peers flooding bad addresses) | Bucket system with new/tried tables; rate limiting; ban malicious peers |
| Compact block reconstruction failures | Fall back to full block download via `getdata` (MSG_BLOCK) |

**Assumptions**:
- Phase 4 P2P infrastructure is stable and well-tested before Phase 6 begins
- BIP 330 remains Draft — implementation is aspirational, not committed
- Mainnet mempool sync is impractical for mobile; server-side deployment assumed for full P2P operation
- Address database persistence is optional (in-memory is acceptable for initial release)

---

### Design Alignment: Cluster Mempool

Bitcoin Core is actively developing **cluster mempool** (delvingbitcoin.org wg-cluster-mempool, 2023-2026) — a replacement for the current mempool that groups transactions into clusters (connected components by parent-child relationships) and uses linearization for block template construction.

**Impact on Phase 6**: The mempool sync design should align with cluster mempool concepts:
- Store transaction clusters rather than flat tx list
- Support cluster-aware RBF (replace-by-fee) rules
- Track chunk feerate for fee estimation
- Monitor Bitcoin Core v29+ for cluster mempool activation

### Privacy Consideration: Node Fingerprinting

Active research on delvingbitcoin.org (April-May 2026) addresses P2P node fingerprinting via `addr` message correlation across networks (IPv4 + Tor). Mitigations under discussion include timestamp fuzzing, network-specific timestamp policies, and aging-biased noise.

**Impact on Phase 6**: Address gossip (6.2) should incorporate fingerprinting mitigations:
- Fuzz timestamps when responding to `getaddr` from different network types
- Prefer making addresses older rather than newer (prevents stale address circulation)
- Monitor Bitcoin Core PRs for upstream fingerprinting fixes

### Future: Utreexo Stateless Validation

[Utreexo](https://github.com/mit-dci/libutreexo) enables stateless block validation via UTXO accumulator proofs — nodes store only accumulator roots, not the full UTXO set. This could reduce BitcoinKernel's chainstate from ~10 GB to minimal.

- **Status**: Production in Floresta (via `rustreexo`). No BIP, no Bitcoin Core integration.
- **Relevance to Phase 6**: Utreexo would change how UTXOs are resolved — replacing LevelDB chainstate lookups with proof verification. This is orthogonal to P2P networking but would complement the mempool and peer infrastructure built here.
- **Swift-native path**: Would require a Swift implementation of the Utreexo forest (reference `libutreexo` C99, `rustreexo` Rust).
- **Not committed**: Too early for a dedicated phase. Monitor Floresta and Bitcoin Core for Utreexo standardization.

---

## BIP Coverage

| BIP | Name | Priority | Notes |
|-----|------|----------|-------|
| 152 | Compact Block Relay | SHOULD | High-bandwidth mode, depends on mempool (6.1) |
| 155 | addrv2 | MUST | Extended addresses for Tor v3, I2P (peer discovery) |
| 330 | Erlay | MAY | Draft status — feature-gated, monitor for finalization |

---

## Phase Notes / Change Log

- 2026-05-07: Initial creation. Deferred features from Phase 4 scope discussion. Mempool sync and addr gossip are the core additions. BIP 152 promoted from Phase 4 nice-to-have (now feasible with mempool). BIP 330 (Erlay) included as aspirational with Draft-status risk noted.