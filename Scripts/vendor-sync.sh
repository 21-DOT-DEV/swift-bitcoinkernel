#!/usr/bin/env bash
# vendor-sync.sh — the source-sync recipe: vendir + patch re-apply + fixups.
#
# Replaces `swift package plugin subtree-sync` (the subtree CLI plus the
# committed Vendor/bitcoin mirror). Usage:
#
#   Scripts/vendor-sync.sh            # normal sync (bump `ref:` in vendir.yml first)
#   Scripts/vendor-sync.sh --locked   # reproduce the committed lock (CI gate)
#
# Three stages:
#
#   1. `vendir sync -d .vendir-upstream/bitcoin` — the lone `git:` entry
#      fetches bitcoin/bitcoin at the pinned ref into the gitignored
#      `.vendir-upstream/` checkout. This is the only network fetch. The
#      tree is pristine only between stage 1 and stage 2 — after a run it
#      holds patched bytes, so validating patches against pristine
#      upstream (the role `patches/UPSTREAMING.md` documents) requires a
#      detached `git worktree` of this checkout's locked HEAD, or
#      re-running stage 1 (`vendir sync -d .vendir-upstream/bitcoin`).
#
#   2. `git apply --directory=.vendir-upstream/bitcoin patches/bitcoin/*.patch`
#      — re-apply the five maintained patches to the pristine clone before
#      anything slices it. One `--check` across the whole set runs first,
#      so a patch that no longer applies aborts before ANY write — that
#      failure IS the drift tripwire (the constitution's "reapply after
#      every extraction" requirement).
#
#   3. `vendir sync -d <each slice>` — `directory:` slices copy the
#      PATCHED cache into Sources/ and Tests/ (local copies, no refetch),
#      then the two fixups vendir's path rules cannot express:
#        - the synthetic `include/leveldb/helpers/memenv/` copy (upstream
#          ships memenv.h only under helpers/; dbwrapper.cpp needs it at
#          `<leveldb/helpers/memenv/memenv.h>` — see patches/README.md);
#        - the flat test fixtures (four JSONs from two upstream dirs; the
#          test bundle loads them flat via subdirectory:"Fixtures").
#
# bash 3.2-safe (macOS ships bash 3.2).

set -euo pipefail
cd "$(dirname "$0")/.."

# Only --locked is accepted. Directory selection is fixed below on purpose:
# a bare `vendir sync` in stage 3 would re-select the git: checkout too,
# wiping the just-applied patches before the slices copy — and arbitrary
# `-d` passthrough would reorder that same class of bug.
LOCKED_FLAG=""
if [[ "${1:-}" == "--locked" ]]; then
    LOCKED_FLAG="--locked"
    shift
fi
if [[ $# -ne 0 ]]; then
    echo "usage: $0 [--locked]" >&2
    exit 2
fi

# vendir's git-bundle cache: the stage-1 fetch saves the upstream pack
# under $VENDIR_CACHE_DIR/.vendir-cache/ keyed by sha256(url), so later
# runs unbundle and fetch only the delta instead of re-cloning ~250 MB.
# Default to the repo root so the maintainer's checkout, a scratch
# worktree replay (Scripts/vendir-check.sh), and CI's actions/cache all
# share one cache location. The 1 Mi default cap would evict the ~120 MB
# bundle instantly — raise it (overridable for constrained envs).
export VENDIR_CACHE_DIR="${VENDIR_CACHE_DIR:-$PWD}"
export VENDIR_MAX_CACHE_SIZE="${VENDIR_MAX_CACHE_SIZE:-512Mi}"

echo "==> vendir sync (upstream checkout)"
vendir sync $LOCKED_FLAG -d .vendir-upstream/bitcoin

echo "==> git apply patches/bitcoin/*.patch"
# One --check across ALL patches, then one apply: a per-patch loop that
# checked and applied in turn would leave patches 1..N-1 written when
# patch N's check fails — a partial write. Checking the whole set first
# keeps a failed patch from mutating the pristine tree at all.
git apply --check --directory=.vendir-upstream/bitcoin patches/bitcoin/*.patch
for patch in patches/bitcoin/*.patch; do
    echo "    $patch"
done
git apply --directory=.vendir-upstream/bitcoin patches/bitcoin/*.patch

echo "==> vendir sync (directory slices)"
# `-d` on every directory: destination — never the bare sync. A bare
# `vendir sync` re-syncs `.vendir-upstream/bitcoin` as well, re-checking
# out the pristine ref over the patched tree so UNPATCHED bytes land in
# Sources/ (observed: logging.cpp, rpc/server.h, compat.h regressed).
# Each `-d` destination still gets its full wipe+replace.
vendir sync $LOCKED_FLAG \
    -d Sources/crc32c \
    -d Sources/leveldb \
    -d Sources/minisketch \
    -d Sources/secp256k1 \
    -d Sources/libbitcoinkernel \
    -d Sources/bitcoind \
    -d Tests/BitcoinTests/Fixtures

echo "==> fixups"
# Synthetic include copy so <leveldb/helpers/memenv/memenv.h> resolves
# through the include/ public-headers root (see patches/README.md).
mkdir -p Sources/leveldb/include/leveldb/helpers/memenv
cp Sources/leveldb/helpers/memenv/memenv.h \
   Sources/leveldb/include/leveldb/helpers/memenv/memenv.h

# Flat fixture dir — vendir can't merge two upstream dirs into one
# destination, so they arrive repo-relative and move up here.
mv Tests/BitcoinTests/Fixtures/test/functional/data/*.json \
   Tests/BitcoinTests/Fixtures/
mv Tests/BitcoinTests/Fixtures/src/test/data/*.json \
   Tests/BitcoinTests/Fixtures/
rm -rf Tests/BitcoinTests/Fixtures/test Tests/BitcoinTests/Fixtures/src

echo "==> vendor-sync done"
