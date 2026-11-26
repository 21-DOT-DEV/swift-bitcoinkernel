#!/usr/bin/env bash
# vendir-check-test.sh — fixture tests for Scripts/vendir-check.sh.
# Each case builds a minimal synthetic repo under mktemp and runs the
# real gate against it through the sanctioned seams (VENDIR_CHECK_ROOT
# + VENDIR_CHECK_ALLOW_PROTOCOLS=file:… — see the check's env docs).
#
# Required by the jury round-3 review: a recipe whose slice list drops
# a declared destination must NOT read clean — the sync check's
# pre-delete coverage turns the skip into ` D` lines the whole-worktree
# status must catch. The same fixture's positive leg proves ignorePaths
# files survive pre-delete (Sources/one/kept.txt is committed but never
# arrives from upstream): without the exclusion, every preserved file
# would false-positive ` D`. The positive leg invokes the gate bare —
# every check, the way CI calls it — so the non-sync checks are
# exercised on the stock bash too, not just verified once by hand.
#
# Usage: Scripts/vendir-check-test.sh   (exits 0 = all cases pass)

set -u
cd "$(dirname "$0")/.." || exit 2
GATE=$PWD/Scripts/vendir-check.sh
command -v git >/dev/null || { echo "git required" >&2; exit 2; }
command -v vendir >/dev/null || { echo "vendir required (a real sync runs)" >&2; exit 2; }

# Hermetic git: fixture commits must not inherit the caller's git
# config — a global commit.gpgsign stalls on a signing key, a global
# core.hooksPath runs host hooks inside the fixture, an injected
# GIT_CONFIG_* leaks into assertions, and GIT_DIR/GIT_WORK_TREE (set by
# an outer hook or `rebase -x`) would redirect `git -C` calls into the
# wrong repo. Null the config files and drop the repo-location vars.
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_DIR GIT_WORK_TREE \
    GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_TEMPLATE_DIR \
    GIT_ALLOW_PROTOCOL GIT_SSH_COMMAND

FIX=$(mktemp -d "${TMPDIR:-/tmp}/vccheck-test.XXXXXX") || exit 2
trap 'rm -rf "$FIX"' EXIT
fail=0

gc() { git -C "$1" -c user.email=vccheck@test -c user.name=vccheck -c core.hooksPath=/dev/null "${@:2}"; }

# --- fixture: a bare upstream and a consuming repo --------------------
# Upstream carries two files under tag v1 (plus src/k1.cpp — the
# dual-list pair below needs a literal src/**/*.cpp on each side). The
# repo declares one git: checkout dir and two directory: slices;
# Sources/one also lists ignorePaths with a committed file upstream
# never ships, and the two slices carry the mirroring literal
# src/**/*.cpp include/exclude lists duallist asserts.
mkdir -p "$FIX/up.git" "$FIX/upw/src" "$FIX/repo/Scripts" "$FIX/repo/Sources/one"
git -C "$FIX/up.git" init -q --bare -b main || exit 2
git -C "$FIX/upw" init -q -b main || exit 2
printf 'one\n' > "$FIX/upw/one.txt"
printf 'two\n' > "$FIX/upw/two.txt"
printf 'k1\n' > "$FIX/upw/src/k1.cpp"
gc "$FIX/upw" add -A && gc "$FIX/upw" commit -qm upstream || exit 2
gc "$FIX/upw" tag v1
git -C "$FIX/upw" remote add origin "file://$FIX/up.git"
git -C "$FIX/upw" push -q origin main v1 || exit 2
# shadow's scratch leg fetches the locked SHA with --filter=blob:none —
# the bare remote needs partial-fetch + want-sha enabled for that to
# work over file:// (GitHub allows both by default upstream).
git -C "$FIX/up.git" config uploadpack.allowFilter true
git -C "$FIX/up.git" config uploadpack.allowTipSHA1InWant true
git -C "$FIX/up.git" config uploadpack.allowReachableSHA1InWant true

R=$FIX/repo
git -C "$R" init -q -b main || exit 2
cat > "$R/vendir.yml" <<EOF
apiVersion: vendir.k14s.io/v1alpha1
kind: Config
minimumRequiredVersion: "0.40.0"
directories:
- path: .vendir-upstream/up
  contents:
  - path: .
    git:
      url: file://$FIX/up.git
      ref: v1
- path: Sources/one
  contents:
  - path: .
    directory:
      path: .vendir-upstream/up
    includePaths: [one.txt, src/k1.cpp]
    ignorePaths: [kept.txt]
- path: Sources/two
  contents:
  - path: .
    directory:
      path: .vendir-upstream/up
    includePaths: [two.txt, 'src/**']
    excludePaths: [src/k1.cpp]
EOF
cat > "$R/.gitignore" <<'EOF'
.vendir-upstream/
.vendir-tmp*
.vendir-cache/
EOF
printf 'kept\n' > "$R/Sources/one/kept.txt"
cat > "$R/Scripts/vendor-sync.sh" <<'EOF'
#!/bin/bash
# Fixture recipe — mirrors the real one's shape: the upstream checkout
# first, then per-slice -d syncs, one destination per line so a case
# can drop a slice with sed.
set -euo pipefail
cd "$(dirname "$0")/.."
LOCKED=""
[ "${1:-}" = "--locked" ] && { LOCKED="--locked"; shift; }
vendir sync $LOCKED \
    -d .vendir-upstream/up
vendir sync $LOCKED \
    -d Sources/one \
    -d Sources/two
EOF

# Populate once so the lock and vendored files are committed state.
(cd "$R" && GIT_ALLOW_PROTOCOL=file:https VENDIR_CACHE_DIR="$R" \
    vendir sync -d .vendir-upstream/up -d Sources/one -d Sources/two) \
    || { echo "fixture vendir sync failed" >&2; exit 2; }
gc "$R" add -A && gc "$R" commit -qm 'fixture: synced tree' || exit 2

run_gate() {
    VENDIR_CHECK_ROOT="$R" VENDIR_CHECK_ALLOW_PROTOCOLS=file:https \
        VENDIR_CHECK_UPSTREAM_URLS="file://$FIX/up.git" \
        VENDIR_CHECK_UPSTREAM_DIRSRC=".vendir-upstream/up" \
        VENDIR_CHECK_DESTINATIONS=".vendir-upstream/up Sources/one Sources/two" \
        VENDIR_CHECK_DUALLIST_INCLUDE_ENTRY=Sources/one \
        VENDIR_CHECK_DUALLIST_EXCLUDE_ENTRY=Sources/two \
        /bin/bash "$GATE" "$@" 2>&1
}

echo "== case: clean fixture passes all checks (bare run = the CI invocation)"
out=$(run_gate) && rc=0 || rc=$?
if [ "$rc" = 0 ]; then
    echo "   ok"
else
    echo "   FAIL: exited $rc"; printf '%s\n' "$out"; fail=1
fi

# shadow's store resolution has two legs: the live checkout's object
# store (vendir leaves .git in the upstream dir — exercised above) and
# a scratch bare repo fed by one depth-1 blob:none fetch — CI's normal
# checkout-less path. Remove the live store to force the scratch leg.
echo "== case: shadow probes via the scratch blob:none fetch (no live store)"
rm -rf "$R/.vendir-upstream/up"
out=$(run_gate shadow) && rc=0 || rc=$?
if [ "$rc" = 0 ]; then
    echo "   ok"
else
    echo "   FAIL: exited $rc"; printf '%s\n' "$out"; fail=1
fi

echo "== case: recipe dropping a -d slice fails, naming the destination"
sed '/-d Sources\/two/d' "$R/Scripts/vendor-sync.sh" > "$R/Scripts/vendor-sync.sh.tmp"
mv "$R/Scripts/vendor-sync.sh.tmp" "$R/Scripts/vendor-sync.sh"
gc "$R" add -A && gc "$R" commit -qm 'fixture: recipe drops Sources/two' || exit 2
out=$(run_gate sync) && rc=0 || rc=$?
if [ "$rc" != 1 ]; then
    echo "   FAIL: exited $rc — a skipped destination must be a finding"
    printf '%s\n' "$out"; fail=1
elif ! printf '%s\n' "$out" | grep -q ' D Sources/two/'; then
    echo "   FAIL: exited 1 but no ' D Sources/two/' deletion lines"
    printf '%s\n' "$out"; fail=1
else
    echo "   ok (exited 1, skipped destination surfaced as deletions)"
fi

echo
if [ "$fail" = 0 ]; then
    echo "vendir-check-test: all cases pass"
else
    echo "vendir-check-test: FAILURES above" >&2
    exit 1
fi
