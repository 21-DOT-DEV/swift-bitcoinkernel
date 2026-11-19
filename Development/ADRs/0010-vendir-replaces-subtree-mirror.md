---
adr: 0010
title: Vendir replaces subtree extraction and the committed Vendor mirror
status: Accepted
date: 2026-11-16
supersedes: []
superseded_by: null
---

# 0010 — Vendir replaces subtree extraction and the committed Vendor mirror

## Context

Bitcoin Core reached the package through `swift-plugin-subtree`: a squash
merge of the entire `bitcoin/bitcoin` tree into `Vendor/bitcoin` (~53 MB,
1,459 tracked files — including ~150 Python scripts and contrib/test
tooling nothing extracts), plus a `subtree.yaml` manifest of extraction
rules copying ~14 MB of it into `Sources/` and `Tests/`. The only recorded
provenance was the manifest's `commit:` field — the tag object SHA — and
squash-commit trailers; there was no lockfile, no CI freshness check, and
the mirror's unused bulk rode every clone. The sibling `swift-secp256k1`
repository made the same move first (its spec 002) with five small
upstreams; this repository's single large upstream, five maintained
patches, and two layouts the tool cannot express required the design to
be re-derived rather than copied.

## Decision

Vendoring is declarative via `vendir.yml` + committed `vendir.lock.yml`
(which records the resolved upstream commit): `Vendor/` and
`subtree.yaml` are to be deleted, the `swift-plugin-subtree` dev
dependency dropped, and extracted trees land directly under `Sources/`
and `Tests/`
at the same paths. The maintainer-facing command is
`Scripts/vendor-sync.sh`: fetch the pinned tag once into a gitignored
checkout, `git apply` every `patches/bitcoin/*.patch` to that pristine
tree, slice the destinations, then run two fixups (the synthetic LevelDB
`include/` copy and the flat test-fixture directory) that vendir's
no-overlapping-paths rule cannot express. Hand-written destination files
survive via `ignorePaths`; patched files deliberately do not — they are
re-created by patch application on every sync, so upstream drift under a
patch fails loudly at sync time. A `vendir-check` workflow replays the
locked recipe in CI and requires a clean `git status`.

## Alternatives considered and rejected

Keeping `swift-plugin-subtree` and the committed mirror. Rejected: the
plugin was never wired into CI here, the mirror carried ~39 MB of
never-extracted files, and squash merges lose per-file provenance the
lock now records. Keeping an upstream-style committed `git subtree`
mirror as the source of truth. Rejected: Bitcoin Core maintains its own
subtrees (`src/leveldb`, `src/secp256k1`, …) because Core developers
patch inside them and changes flow upstream bidirectionally; this
repository is a one-directional consumer whose diffs live as `.patch`
artifacts applied downstream — a mirror earns nothing a gitignored
checkout cannot provide. Preserving patched files via `ignorePaths`.
Rejected: it silently pins stale patched bytes; every packaging
precedent (Debian `quilt`, Bazel `http_archive`, Apple's
`vendor-boringssl.sh`) applies patch artifacts to pristine source and
fails visibly on drift.

## Consequences

`Vendor/` and its unused Python files leave the working tree — ~53 MB
less per checkout and per shallow or partial clone (full clones keep
the blobs in history); `vendir.lock.yml` is the provenance record and
`v31.0` pins by tag plus resolved commit. The local-patches discipline becomes
mechanical (wipe + re-apply) rather than a policy reminder.
`patches/UPSTREAMING.md`'s validation target moves from `Vendor/bitcoin`
to the gitignored `.vendir-upstream/bitcoin`. GPG verification of the
signed tag and a self-test harness for the CI gate remain deferred.
