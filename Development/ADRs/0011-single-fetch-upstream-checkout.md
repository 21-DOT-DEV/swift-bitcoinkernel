---
adr: 0011
title: A single git-sourced upstream checkout feeds all vendir directory slices
status: Accepted
date: 2026-11-16
supersedes: []
superseded_by: null
---

# 0011 — A single git-sourced upstream checkout feeds all vendir directory slices

## Context

vendir performs one network fetch per `git:` contents entry with no
cross-entry object cache (carvel-dev/vendir#101), and released versions —
including v0.47.0 — fetch *every* remote ref shallowly for a named tag
(carvel-dev/vendir#453's targeted fetch is merged on a branch but
unshipped). `bitcoin/bitcoin` carries ~715 refs, so a single fetch is a
several-hundred-MB pack. This repository has seven slice destinations;
the sibling `swift-secp256k1`'s canonical shape — one `git:` entry per
destination — would download the same pack roughly seven additional
times per sync.

## Decision

`vendir.yml` holds exactly one `git:` contents entry: `bitcoin/bitcoin`
at the pinned tag into `.vendir-upstream/bitcoin`, listed first (vendir
syncs directories in config order). Every destination — the six source
targets and the test fixtures — is a `directory:` contents slicing a
filtered subset of that checkout; `newRootPath` re-roots the vendored
libraries. The checkout is gitignored scratch that also serves as the
`git apply --check` validation tree `patches/UPSTREAMING.md` documents —
pristine only between the fetch and patch stages of each sync (a
finished run leaves patched bytes; re-running `vendir sync -d
.vendir-upstream/bitcoin` restores the pristine tree for validation).
Because the cache entry is itself a `git:` source, `vendir.lock.yml`
records the real upstream commit SHA — so the CI gate's ref↔lock
resolution check keeps its meaning.

## Alternatives considered and rejected

One `git:` entry per destination (the canonical vendir shape, used by
the sibling). Rejected on fetch economics: ~7 extra multi-hundred-MB
fetches per sync; the sibling's upstreams total ~25 MB. An `http:`
tarball of the release (~15 MB per sync). Rejected on provenance: the
lock would pin a tarball sha256 rather than a commit, the ref↔lock CI
check could not re-resolve the tag to a commit, and GitHub-generated
archives have changed checksums before (the 2023 `git archive`
compression change). A script-managed clone plus a provenance sidecar —
`swift-openssl`'s older shape. Rejected as superseded by the git-sourced
cache: the lockfile *is* the sidecar, and plain `vendir sync` remains
meaningful.

## Consequences

A sync costs one fetch plus local copies; the lockfile keeps real commit
provenance, and `patches/` validation re-establishes a pristine upstream
tree via the checkout stage of `vendor-sync.sh`. `.vendir-upstream/` is disposable — deleted state, not vendored
state. When a vendir release ships targeted fetch (#453), the pack
shrinks further with no config change beyond a version bump.
