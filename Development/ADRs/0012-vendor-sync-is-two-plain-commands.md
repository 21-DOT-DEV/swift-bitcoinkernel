---
adr: 0012
title: The Bitcoin Core sync is two plain commands, with patches applied to the copied sources
status: Accepted
date: 2026-11-26
supersedes: [10]
superseded_by: null
---

# 0012 — The Bitcoin Core sync is two plain commands, with patches applied to the copied sources

## Context

ADR 0010 moved vendoring to vendir and made `Scripts/vendor-sync.sh` the
maintainer command. The script existed for three things vendir cannot do
in one pass: apply the five `patches/bitcoin/*.patch` files to the
downloaded checkout between the fetch and the copies, duplicate one
LevelDB header into a second location, and flatten four JSON test files
from two upstream folders into one. Each forced ordering the config
could not express, so a bare `vendir sync` produced a wrong tree, the
checkout was left holding patched files, and the planned CI gate had
grown into a 1,478-line check script before it landed. vendir has no
patch or post-sync step (carvel-dev/vendir#250 is open), so a patch
step is always a second command; the question was where it runs.

## Decision

The sync is `vendir sync && git apply patches/bitcoin/*.patch`, and the
script is deleted. `vendir.yml` and `vendir.lock.yml` stay the authority
ADR 0010 made them, and ADR 0011's single download feeding local copies
stands. Patches apply after the copy, directly onto `Sources/`, so each
`.patch` carries this repository's paths (`Sources/bitcoind/src/init.cpp`)
and `git apply -p3` strips them back to upstream's. The download folder
`.vendir-upstream/bitcoin` is filtered at fetch time to source files,
license texts, the test data, and three build-setting templates, and is
never patched. The two layout fixups become config: the duplicated
LevelDB header and the kernel's public C header are hand-written
one-line forwarding headers kept by `ignorePaths`, and the test data
syncs into `Fixtures/rpc/` and `Fixtures/blockfilters/`. Verification
is the same command with `--locked` followed by `git status --porcelain`,
which prints nothing when the committed files reproduce;
`.github/workflows/vendir-check.yml` runs it.

## Alternatives considered and rejected

Keeping the patch step before the copy (ADR 0010's shape). Rejected: it
is the only reason the sync needs three ordered stages, and the tools
that copy an upstream into a different layout patch the copy instead.
Apple's `vendor-boringssl.sh` in swift-crypto and swift-nio-ssl runs
`git apply` after its filtered copy with `Sources/...` paths in the
patch files, Firefox's `mach vendor` applies patches "relative to the
vendor-directory", and dfetch converts back to upstream form with a
separate command. Preserving the patched files through `ignorePaths`
so that `vendir sync` alone suffices. Rejected for the reason ADR 0010
gave: a preserved file silently stays at the old release. Keeping the
check script. Rejected: re-running the sync and requiring no difference
is the gate Kubernetes (`hack/verify-vendor.sh`), OpenShift, and Firefox
(`vendor-verify`) use, the lock file already pins the commit against a
moved tag, and the script's one check with no equivalent (a new upstream
file hidden behind a hand-written one) can only arise at a version bump.
Keeping byte copies of the two headers. Rejected: a stale copy of the
kernel's C header would have Swift call functions as the old release
declared them, which the compiler cannot detect across a C boundary.

## Consequences

Anyone with vendir and git can sync or verify from the two lines at the
top of `vendir.yml`; nothing else encodes ordering. A new Bitcoin Core
release that changes code under a patch stops `git apply` with the
file's name. Patch files no longer apply to an upstream checkout as
written: `patches/UPSTREAMING.md` carries the `-p3` commands, and a
patched file that moves between the `bitcoind` and `libbitcoinkernel`
targets needs its patch path edited. The download folder is no longer a
git checkout, so anything needing the full upstream tree (the CMake
memo's build) clones the tag itself. The forwarding headers include a
file outside the public header folder, which holds while the package is
built from source and would not survive packaging the headers alone
into a binary framework. A hand-written file inside a vendored folder
must match an `ignorePaths` entry or the next sync deletes it; the CI
check reports that as a difference.
