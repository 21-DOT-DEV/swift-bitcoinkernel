# Phase 5: Compact Block Filters

**Goal**: Implement BIP 157 (Client Side Block Filtering) and BIP 158 (Compact Block Filters for Light Clients) in pure Swift, enabling privacy-preserving wallet sync without revealing which addresses belong to the wallet.

**Status**: PLANNED  
**Last Updated**: 2026-05-07

---

## Goal

Enable wallets to discover relevant transactions by downloading compact block filters (Golomb-Rice coded sets of script pubkeys) and scanning them locally — rather than querying an Esplora API or downloading full blocks. This provides the privacy story for `BitcoinKernel` as a node layer: wallets sync privately, fetching only matched blocks.

Builds on Phase 4's P2P wire protocol — compact filter messages (`getcfheaders`, `getcfilters`, `getcfcheckpt`) are P2P protocol extensions.

---

## Key Features

### 5.1 Golomb-Rice Coder (BIP 158)

**Purpose & User Value**: Implement the Golomb-Rice coding scheme used by BIP 158 compact filters — encoding and decoding of parameterized Golomb-Rice sets — in pure Swift.

**Success Metrics**:
- `GolombCodedSet` type with `encode(_ items:)` and `decode(_ data:)` methods
- Parameterized by `P` value (per BIP 158: `P = 2^19` for basic filters)
- Correct encoding: sorted items, differential encoding, Golomb-Rice bitstream
- Correct decoding: reconstruct sorted set from bitstream
- Round-trip property: decode(encode(set)) == set
- Test vectors from BIP 158 pass (blockfilters.json from Bitcoin Core)

**Dependencies**: None (pure algorithm)

**Reference**: BIP 158 specification, Bitcoin Core's `src/blockfilter.cpp`, Kyoto's filter parsing

---

### 5.2 Basic Filter Construction

**Purpose & User Value**: Construct BIP 158 "basic" filters from block data — extracting the set of output script pubkeys and prevout script pubkeys for each block and encoding them as a Golomb-Rice set.

**Success Metrics**:
- `BasicFilter` type: `init(block: Block)` constructs filter from block data
- Extracts all `scriptPubKey` outputs from block transactions
- Extracts all prevout `scriptPubKey` inputs (UTXOs being spent)
- Encodes as Golomb-Rice set with `P = 2^19`
- `filterHash()` returns the double-SHA256 of the serialized filter
- `filterHeader(previousHeader:)` returns SHA256d(filterHash || previousHeader) per BIP 157
- Validates against `getblockfilter` RPC results on regtest/signet

**Dependencies**: 5.1 Golomb-Rice Coder, Phase 3 (Block type from BitcoinKernel)

---

### 5.3 Filter Header Chain

**Purpose & User Value**: Download and verify the chain of compact filter headers — the cryptographic commitment that ties each filter to its block and the previous filter — ensuring filter integrity.

**Success Metrics**:
- `getcfheaders` / `cfheaders` P2P messages (BIP 157)
- `FilterHeaderChain` type: stores and validates filter headers
- Verification: each filter header = SHA256d(filterHash || previousFilterHeader)
- Genesis filter header: defined per BIP 157 for each chain type
- `FilterCheckpoint` messages for fast catch-up (`getcfcheckpt` / `cfcheckpt`)
- Stores filter headers for lookback window (configurable, default: 1008 blocks / 1 week)

**Dependencies**: 5.2 Basic Filter Construction, Phase 4 (P2P wire protocol for `getcfheaders`)

---

### 5.4 Filter Download & Matching

**Purpose & User Value**: Download compact filters for blocks of interest, match them against wallet scripts, and request only matched blocks — enabling private wallet sync.

**Success Metrics**:
- `getcfilters` / `cfilters` P2P messages (BIP 157)
- `CompactFilterClient` type: downloads filters for a block range
- `matchFilter(_ filter: BasicFilter, against scripts: [ScriptPubkey]) -> Bool`
- Efficient matching: decode filter, check membership for each script
- Configurable lookahead window for HD wallet gap limit
- Returns list of matched block hashes for full block download
- Works with existing `BlockSource.block(for:)` for matched block fetch

**Dependencies**: 5.3 Filter Header Chain, Phase 4 (P2P wire protocol for `getcfilters`)

**Reference**: Kyoto's `chain/` module filter matching, BDK-Kyoto's integration pattern

---

### 5.5 CBFBlockSource — Filter-Based BlockSource

**Purpose & User Value**: Provide a `BlockSource` conformer that uses compact filters for wallet-driven sync — download filters first, match against wallet scripts, fetch only matched blocks.

**Success Metrics**:
- `CBFBlockSource` conforms to `BlockSource`:
  - Uses filter header chain for `bestTip()`
  - Fetches blocks only for matched hashes
  - Falls back to full block download for unmatched ranges (IBD bootstrap)
- Configurable with wallet scripts for matching
- Integrates with `BlockchainSync` (drop-in, same as `EsploraBlockSource` and `P2PBlockSource`)
- False-positive rate meets BIP 158 spec (1/2^20 per element)

**Dependencies**: 5.4 Filter Download & Matching, Phase 4 (P2P infrastructure)

---

### 5.6 CBF Example App

**Purpose & User Value**: Demonstrate compact-filter-based wallet sync in a working example app.

**Success Metrics**:
- Example app: CBFBlockSource with BlockchainSync on signet
- Wallet script input (hardcoded or configurable)
- Matched block display: which blocks contained relevant transactions
- Privacy metrics: number of blocks downloaded vs total chain height
- Tor integration (filters downloaded through SOCKS5 proxy)

**Dependencies**: 5.5 CBFBlockSource

---

## Phase Dependencies & Sequencing

```
5.1 Golomb-Rice Coder (no deps)
    └── 5.2 Basic Filter Construction
            └── 5.3 Filter Header Chain
                    └── 5.4 Filter Download & Matching
                            └── 5.5 CBFBlockSource
                                    └── 5.6 CBF Example App
```

5.1 is pure algorithm, can be developed independently. 5.3-5.4 depend on Phase 4's P2P wire protocol for `getcfheaders`/`getcfilters` messages.

---

## Phase-Level Metrics & Success Criteria

| Metric | Target |
|--------|--------|
| Build success | All Tier 1 platforms (macOS, iOS) |
| Test coverage | ≥80% of CBF API surface |
| BIP 158 test vectors | All pass (blockfilters.json) |
| CBF Sync Time (signet) | Baseline established |
| False-positive rate | ≤ BIP 158 spec (1/2^20 per element) |
| Privacy ratio | Matched blocks / total blocks (target: wallet-dependent) |
| Documentation | All public types documented (DocC) |
| Example app | CBF sync demo on signet |

---

## Risks & Assumptions

| Risk | Mitigation |
|------|------------|
| Golomb-Rice implementation bugs | Validate against BIP 158 test vectors (blockfilters.json) |
| Filter header chain divergence during reorg | Store lookback window (1008 blocks); re-download on divergence |
| False-positive matches causing unnecessary block downloads | Tune P parameter; BIP 158 spec already provides 1/2^20 FPR |
| P2P peers not supporting compact filters (`NODE_COMPACT_FILTERS` service bit) | Fall back to full P2PBlockSource for IBD bootstrap |
| Filter download bandwidth (one filter per block) | Each filter is ~10-20 KB; signet chain is small; mainnet deferred |

**Assumptions**:
- Phase 4 P2P wire protocol is complete before filter messages are implemented
- `NODE_COMPACT_FILTERS` service bit peers are available on signet/mainnet
- Golomb-Rice encoding does not require significant performance optimization for signet-scale data
- Wallet scripts are provided by the consuming wallet SDK (BitcoinKernel does not manage keys)

---

### Emerging Alternative: Binary Fuse Filters

Research posted on delvingbitcoin.org (April 2026) suggests **Binary Fuse filters** may offer a superior alternative to Golomb-Rice Coded Sets:

- **CPU reduction**: 9-80× on desktop, 6-45× on ARM (Raspberry Pi 5)
- **Bandwidth**: negligible increase (~2-3%)
- **False-positive rate**: 16-bit Fuse16 = 1/65536 vs GCS = 1/784931 (20-bit Fuse20 matches GCS FPR)
- **Status**: Research only — no BIP, no deployment. Active discussion on delvingbitcoin.org.

**Impact on Phase 5**: Implement BIP 158 GCS first (the deployed standard). Design the filter API to be algorithm-agnostic (`FilterProtocol`) so Binary Fuse can be swapped in if/when standardized. Monitor delvingbitcoin.org for BIP proposal progress.

---

## BIP Coverage

| BIP | Name | Priority | Notes |
|-----|------|----------|-------|
| 157 | Client Side Block Filtering | MUST | `getcfheaders`, `getcfilters`, `getcfcheckpt` messages |
| 158 | Compact Block Filters for Light Clients | MUST | Golomb-Rice coding, basic filter construction |

---

## Phase Notes / Change Log

- 2026-05-07: Initial creation. Swift-native BIP 157/158 compact block filter implementation. Builds on Phase 4 P2P infrastructure. No Rust FFI — algorithm implementation from spec. Reference implementations: Kyoto, fltr ecosystem (for filter matching patterns only).