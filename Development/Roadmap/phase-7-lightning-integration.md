# Phase 7: Lightning Integration

**Goal**: Make `BitcoinKernel` a first-class Bitcoin backend for Core Lightning (CLN) by implementing the CLN Bitcoin backend plugin interface, adding UTXO lookup APIs to the kernel, and providing Lightning-aware fee estimation.

**Status**: FUTURE  
**Funding**: 7.1 (UTXO Lookup API) is pulled into the 2026 funding window — scheduled in Q8 of the shared 2026 roadmap; developable independently since Phase 3 (complete)  
**Last Updated**: 2026-05-07

---

## Goal

Enable CLN to use `BitcoinKernel` as its Bitcoin backend — replacing `bitcoind` with an embedded kernel node layer. CLN's plugin-based architecture makes this feasible: it communicates with Bitcoin backends exclusively through 5 JSON-RPC methods, all of which are derivable from `BitcoinKernel` APIs once P2P networking (Phase 4) and mempool sync (Phase 6) are in place.

This phase bridges the gap between "kernel as node layer" and "kernel as Lightning-ready Bitcoin backend."

---

## Key Features

### 7.1 UTXO Lookup API

**Purpose & User Value**: Expose the kernel's UTXO set for point queries — checking whether a specific outpoint is unspent and retrieving its amount and script pubkey. This is the one BitcoinKernel API gap blocking CLN compatibility.

**Success Metrics**:
- `ChainstateManager.getUtxo(outpoint: TransactionOutPoint) -> Coin?` added to public API
- Returns `Coin` (amount + script pubkey) if the outpoint is unspent, `nil` if spent or unknown
- Works against the active chainstate (LevelDB-backed, same database the kernel validates against)
- Thread-safe — callable from any actor/task
- Performance: O(1) LevelDB lookup, p50 < 1ms
- Tested against regtest/signet UTXO set

**Dependencies**: Phase 3 (BitcoinKernel core types: `Coin`, `TransactionOutPoint`, `ChainstateManager`)

**Note**: This API already exists in Bitcoin Core's C++ codebase — `CCoinsViewDB::GetCoin()`. It needs a Swift wrapper exposed through `ChainstateManager`.

---

### 7.2 Filter Registration API

**Purpose & User Value**: Provide a `FilterRegistration` protocol that Lightning nodes and wallets use to register transactions and outputs they care about. When new blocks arrive, only blocks containing registered items trigger callbacks — enabling efficient, bandwidth-conscious block monitoring without full block download.

This mirrors LDK's `Filter` trait (`register_tx`, `register_output`, `filtered_block_connected`) and integrates with compact filters (Phase 5) for privacy-preserving filter-based matching.

**Success Metrics**:
- `FilterRegistration` protocol:
  - `registerTx(txid: Txid, scriptPubkey: ScriptPubkey)` — register a transaction to watch
  - `registerOutput(outpoint: TransactionOutPoint, scriptPubkey: ScriptPubkey)` — register a specific output (more efficient for UTXO-based monitoring)
  - `unregisterTx(txid:)` / `unregisterOutput(outpoint:)` — remove watched items
- `FilteredBlockDelivery` protocol:
  - `filteredBlockConnected(header: BlockHeader, transactions: [Transaction], height: Int)` — callback with only relevant transactions
  - `blockDisconnected(header: BlockHeader, height: Int)` — reorg handling
- Registered items persisted across restarts (optional, for long-running Lightning nodes)
- Integrates with compact filters (Phase 5): registered scripts are used for filter matching; matched blocks deliver only relevant transactions
- Works with both `P2PBlockSource` (Phase 4) and `CBFBlockSource` (Phase 5)

**Dependencies**: Phase 3 (BitcoinKernel core types), Phase 5 (compact filter matching)

**Reference**: LDK's `lightning::chain::Filter` trait and `filtered_block_connected` callback pattern. CLN's `getfilteredblock` is a less efficient alternative (full block download + post-filtering).

**Why LDK's pattern is best**: LDK's `Filter` trait is output-focused — it watches specific script pubkeys, not just transaction IDs. This is more efficient for wallets and Lightning nodes managing multiple addresses. The `filtered_block_connected` callback delivers only relevant data, avoiding full block download. It's the industry standard approach used by LDK, BDK, and Kyoto.

---

### 7.3 CLN Bitcoin Backend Plugin

**Purpose & User Value**: Provide a CLN-compatible plugin that wraps `BitcoinKernel` APIs, implementing the 5 required CLN Bitcoin backend methods. CLN can then use `BitcoinKernel` as a drop-in replacement for `bitcoin-cli` + `bitcoind`.

**Success Metrics**:
- Plugin binary (Swift executable) that registers with CLN's plugin system
- Implements all 5 CLN Bitcoin backend methods:

| CLN Method | BitcoinKernel API Used | Notes |
|------------|----------------------|-------|
| `getchaininfo` | `BlockSource.bestTip()` + `Chain` | Returns chain name, header/block counts, IBD status |
| `getrawblockbyheight` | `BlockSource.blockHash(atHeight:)` + `BlockSource.block(for:)` | Fetches block by height via P2PBlockSource |
| `sendrawtransaction` | `TransactionBroadcaster.broadcast(_:)` | Broadcasts via P2P peers (Phase 4) |
| `getutxout` | `ChainstateManager.getUtxo(outpoint:)` | UTXO lookup (7.1) |
| `estimatefees` | `Mempool` feerate data + P2P `feefilter` messages | Fee estimation (needs Phase 6 mempool) |

- Communicates via CLN's JSON-RPC plugin protocol (Unix socket or stdin/stdout)
- Matches `bcli`'s exact JSON request/response formats for drop-in compatibility
- Configurable: network (mainnet/testnet/signet/regtest), data directory, peer count
- Graceful degradation: if mempool not available, falls back to P2P `feefilter` minimums for fee estimation

**Dependencies**: 7.1 UTXO Lookup API, 7.2 Filter Registration API, Phase 4 (P2P BlockSource + tx broadcast), Phase 6 (mempool sync for fee estimation)

---

### 7.4 Lightning-Aware Fee Estimation

**Purpose & User Value**: Provide fee rate estimates tuned for Lightning's specific confirmation targets — urgent (2 blocks for unilateral close), normal (6-12 blocks for funding/HTLC resolution), and relaxed (100 blocks for cooperative close).

**Success Metrics**:
- `LightningFeeEstimator` type:
  - `estimateUrgent() -> UInt64` — 2-block target (unilateral close, penalty)
  - `estimateNormal() -> UInt64` — 6-12 block target (funding, HTLC resolution)
  - `estimateRelaxed() -> UInt64` — 100-block target (mutual close)
- All rates in sat/kVB (satoshis per kilovirtual byte) per CLN convention
- `feerate_floor`: maximum of mempool min fee and min relay fee
- Derived from P2P mempool data (Phase 6) or P2P `feefilter` messages as fallback
- Regtest: fake fees at 1000 sat/kVB (matching CLN's bcli behavior)

**Dependencies**: Phase 6 (mempool sync for mempoolminfee/minrelaytxfee data)

---

### 7.5 CLN Integration Testing

**Purpose & User Value**: Verify end-to-end that CLN works correctly with a `BitcoinKernel` backend — channel open, HTLC routing, unilateral/mutual close, and fee bumping.

**Success Metrics**:
- Integration test suite: CLN + BitcoinKernel backend on regtest
  - Channel open (funding tx broadcast + UTXO verification)
  - HTLC add/fulfill/fail routing
  - Unilateral close (commitment tx broadcast + CSV delay)
  - Mutual close (cooperative close tx)
  - Fee bumping (CPFP on commitment tx)
- Test harness: spawn CLN with BitcoinKernel plugin, run through standard scenarios
- Performance: channel open latency, HTLC routing throughput baseline

**Dependencies**: 7.3 CLN Bitcoin Backend Plugin

---

### 7.6 LDK-Node Compatibility (Stretch)

**Purpose & User Value**: Optionally verify that `BitcoinKernel` works as a `ChainSource` for LDK-Node, enabling LDK-based Lightning nodes to use kernel-validated blocks.

**Success Metrics**:
- `BitcoinKernelChainSource` conforms to LDK-Node's chain source interface
- Provides: block headers, full blocks, best block, fee estimates
- Transaction broadcast via P2PBlockSource
- Tested against LDK-Node's integration test suite

**Dependencies**: 7.3 CLN Bitcoin Backend Plugin (shared infrastructure), Phase 4 (P2P)

**Risk**: LDK-Node uses Rust FFI — integration path may differ from CLN's plugin model. Consider as aspirational only.

---

## Phase Dependencies & Sequencing

```
Phase 4 (P2P Networking)
    └── Phase 6 (Advanced P2P: mempool sync)
            └── Phase 7 (Lightning Integration)
                    ├── 7.1 UTXO Lookup API (can start earlier — depends on Phase 3)
                    ├── 7.2 Filter Registration API
                    ├── 7.3 CLN Bitcoin Backend Plugin
                    ├── 7.4 Lightning-Aware Fee Estimation
                    ├── 7.5 CLN Integration Testing
                    └── 7.6 LDK-Node Compatibility (stretch)
```

7.1 and 7.2 can be developed independently once Phase 3 is done (kernel API enhancements). 7.3-7.5 depend on Phase 6 for mempool data. 7.6 is aspirational.

---

## Phase-Level Metrics & Success Criteria

| Metric | Target |
|--------|--------|
| Build success | All Tier 1 platforms (macOS, iOS) |
| UTXO lookup latency | p50 < 1ms (LevelDB lookup) |
| CLN plugin registration | CLN accepts plugin, all 5 methods recognized |
| CLN channel open | Successful on regtest with BitcoinKernel backend |
| CLN HTLC routing | Successful multi-hop on regtest |
| CLN unilateral close | Commitment tx broadcast + CSV delay works |
| Fee estimate accuracy | Within 20% of bitcoind estimates on signet |
| Documentation | CLN integration guide, plugin configuration docs |

---

## Risks & Assumptions

| Risk | Mitigation |
|------|------------|
| CLN changes its plugin interface | Pin to specific CLN version; test before upgrading |
| UTXO lookup performance at mainnet scale | LevelDB is O(1) per lookup; mainnet chainstate is ~10GB — acceptable for server-side, impractical for mobile |
| Fee estimation without full mempool may be inaccurate | Document accuracy expectations; fall back to P2P `feefilter` minimums |
| CLN's `getblockfrompeer` optimization not available | Not required — `getblock` with retry timeout is sufficient |
| LDK-Node integration path differs significantly from CLN | Mark 7.6 as aspirational; revisit after CLN integration proven |

**Assumptions**:
- CLN's plugin interface remains stable (5-method contract has been stable for years)
- Phase 6 mempool sync provides sufficient data for fee estimation
- `ChainstateManager`'s internal LevelDB can be exposed for UTXO point queries without significant refactoring
- CLN integration is tested on regtest/signet only; mainnet is server-side deployment
- The CLN plugin is a separate executable (not embedded in CLN's process) — standard CLN plugin model

---

## Phase Notes / Change Log

- 2026-05-07: Initial creation. Based on thorough analysis of CLN's `lightningd/bitcoind.c`, `lightningd/bitcoind.h`, and `plugins/bcli.c`. CLN uses a plugin-based Bitcoin backend with exactly 5 required methods. Key finding: CLN does NOT use ZMQ (timer-based polling only). The one BitcoinKernel API gap is UTXO lookup (`gettxout`).
- 2026-05-07: Added 7.2 Filter Registration API. Based on cross-implementation research (LDK, CLN, BDK, Kyoto, Floresta). LDK's `Filter` trait (`register_tx`, `register_output`, `filtered_block_connected`) is the recommended pattern — output-focused, privacy-preserving, integrates with compact filters (Phase 5). CLN's `getfilteredblock` is a less efficient alternative (full block download + post-filtering).