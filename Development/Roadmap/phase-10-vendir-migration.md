# Phase 10: Vendir Migration

**Goal**: Adopt vendir-driven vendoring for the Bitcoin Core upstream sync — one `git:`-sourced checkout feeding `directory:` slices (blueprint: swift-secp256k1 spec 002, adapted for this repo's scale), retiring the subtree machinery  
**Status**: IN PROGRESS  
**Last Updated**: 2026-11-16  
**Funding**: Inside the 2026 funding window — Q2 (months 4–6) of the shared 2026 roadmap

---

## Key Features

### 10.1 vendir config + sync flow

**Purpose & User Value**: Declarative, reproducible pin of the Bitcoin Core upstream (the current `subtree.yaml` remote and release), extracting into `Sources/{bitcoind,libbitcoinkernel,crc32c,leveldb,minisketch,secp256k1}/` — upstream updates become reviewable, verifiable pull requests.

**Success Metrics**:
- `vendir sync` reproduces the current vendored tree at the pinned Bitcoin Core release (v31.x)
- Local patch carve-outs (`patches/bitcoin/`) and non-patch custom files (modulemaps, `bitcoin-build-config.h`) survive extraction exactly as today

**Dependencies**: None (infrastructure)

### 10.2 Retire subtree machinery

**Purpose & User Value**: Remove `subtree.yaml`, the `swift-plugin-subtree` dev dependency (`subtree-sync` plugin), and related CI once vendir is verified.

**Success Metrics**:
- No subtree references remain in `Package.swift`, `.github/workflows/`, or maintainer docs
- `AGENTS.md` extraction-flow sections describe the vendir flow

**Dependencies**: 10.1 verified

---

## Sequencing

1. Write `vendir.yml` + `Scripts/vendor-sync.sh` (vendir + patch re-apply + fixups); verify identical extraction at the pinned release
2. Remove `Vendor/` mirror, `subtree.yaml`, and the plugin dependency
3. Add the `vendir-check` CI gate; switch docs to vendir

Tracked as spec `Development/Specs/006-vendir-migration/`; durable decisions in ADRs 0010–0011.

---

## Phase-Level Metrics

| Metric | Target |
|--------|--------|
| Vendored tree reproducibility | Matches current extraction at the pinned release |
| Subtree references remaining | 0 |
| Patches/carve-outs intact | 100% after sync |

---

## Risks & Assumptions

| Risk | Mitigation |
|------|------------|
| Extraction-pattern parity (`*.{h,c,cc,cpp}` matching) differs between tools | Verify byte-level parity before retiring subtree; port patterns explicitly |
| Bitcoin Core version bump lands mid-migration | Keep the pinned release fixed until the migration completes |
