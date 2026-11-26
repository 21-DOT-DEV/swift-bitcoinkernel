#!/usr/bin/env bash
# vendir-check.sh [check ...] — the vendored-tree gate behind
# .github/workflows/vendir-check.yml (T011, not yet landed). No arguments
# runs every check that exists, so the gate reproduces outside CI; a
# workflow step names one check per invocation. bash-3.2-safe (macOS
# /bin/bash): no declare -A, no mapfile.
#
# Checks (bare run uses registry order — cheap structural checks first,
# the heavyweight recipe replay last. Explicit args run in the order
# given and may repeat — args are NOT re-sorted, so it is the workflow's
# step order, not $CHECKS, that keeps allowlist first in CI):
#   allowlist committed vendir.yml confined to the declared key set at
#           every mapping level (read un-exploded so `<<:` merge keys
#           surface — and repeated keys fail too, since parsers disagree
#           on which duplicate wins), plus the single-checkout invariants:
#           exactly one contents entry per directory, exactly one source
#           key (git: or directory:) per entry, directories[0] IS the git:
#           checkout, url:/directory.path pinned to the declared upstreams,
#           directories[].path pinned to the eight destinations. vendir
#           drops unknown keys silently, so a typo'd excludePath: would
#           sync green with nothing downstream able to tell.
#   resolve every git:-bearing contents entry's committed ref: resolves
#           upstream to the SHA the committed lock pins — a ref edit
#           without a re-sync, or a moved tag, fails named. directory:
#           slices are skipped: they copy local bytes, nothing resolves.
#   duallist the literal `src/**/*.cpp|.c` set inside libbitcoinkernel's
#           includePaths equals the same filter over bitcoind's
#           excludePaths (negative polarity by design — no vendir
#           construct expresses "this list, negated"). A drifted entry
#           lands a translation unit in both targets (duplicate symbols)
#           or neither (missing symbols) — loud at link time, confusing
#           to attribute.
#   shadow  every declared ignorePaths entry stays absent upstream at the
#           locked SHA — a future upstream file at <newRootPath>/<entry>
#           would be silently shadowed by the preserved local copy
#           (vendir's CopyExistingFiles writes destination bytes over
#           fetched ones — staging_dir.go). Object-level probe:
#           `git ls-tree <locked-sha> -- <path>` answers "does the commit
#           contain this path" exactly — trees ride every fetch, no blob
#           download needed. Probes the live .vendir-upstream/bitcoin
#           object store when it holds the locked SHA (read-only; the
#           patched working tree is ignored), else falls back to a ~200 KB
#           depth-1 blob:none fetch into scratch — and the fetch/presence
#           IS the anchor: a dead pin errors instead of all-404-passing.
#           Local pass first: an entry naming a committed directory or
#           gitlink is a finding — vendir preserves files only. Probes
#           don't consult the slice's includePaths/excludePaths — a hit
#           outside the copy set can over-report (a preserved entry at a
#           coordinate the globs never copy is shadowed by nothing), and
#           that direction fails closed: never a false negative.
#   sync    Scripts/vendor-sync.sh --locked — the WHOLE recipe (fetch,
#           patch re-apply, directory slices, fixups), never bare
#           `vendir sync` — run in a throwaway worktree of HEAD so the
#           wipes can never touch, or be fooled by, an unclean working
#           tree. Coverage is asserted: every tracked, non-preserved
#           destination file is deleted pre-replay, so a recipe that
#           skips a -d slice (or no-ops) leaves ` D` lines, never a
#           false clean. Then a clean --porcelain/--ignored=matching
#           over the WHOLE worktree — only `!!` lines
#           under .vendir-upstream/ (scratch by design) are dropped;
#           any other `!!` is a finding. A recipe
#           failure past the fetch stage (patch apply, slices, fixups)
#           is a finding — committed state no longer reproduces; a
#           stage-1 fetch failure is couldn't-run (network). vendir's
#           own git-bundle cache (VENDIR_CACHE_DIR — pointed at the live
#           repo so the worktree run shares it) makes the ~250 MB
#           stage-1 fetch incremental after the first sync.
#
# Env:
#   VENDIR_CHECK_ROOT   repo (or T-fixture dir) under test — checks read
#                       $ROOT's HEAD:vendir.yml + HEAD:vendir.lock.yml and
#                       run git against $ROOT. Default: this script's repo.
#   VENDIR              vendir binary — a path or a PATH name (default:
#                       vendir). The recipe calls bare `vendir`, so a path
#                       value is PATH-shimmed into the worktree run.
#   VENDIR_CACHE_DIR    vendir's git-bundle fetch cache (default for the
#                       sync check: the live repo root, so scratch
#                       worktree runs reuse the maintainer's cache).
#   VENDIR_MAX_CACHE_SIZE  ceiling for a cacheable fetch (default 512Mi —
#                       vendir's own 1Mi default silently never caches a
#                       ~122 MB bundle).
#   VENDIR_CHECK_ALLOW_PROTOCOLS
#                       Overrides the GIT_ALLOW_PROTOCOL allowlist below
#                       (default https). Fixture remotes widen it to
#                       file:https; nothing else should.
#   VENDIR_CHECK_UPSTREAM_URLS / VENDIR_CHECK_UPSTREAM_DIRSRC
#                       Override the pinned upstream identity (url set +
#                       permitted slice source — DIRSRC is also the
#                       checkout destination the single-fetch shape
#                       pins). Fixture suites repoint these at their
#                       synthetic remotes; like VENDIR_CHECK_ROOT they
#                       come from the invoker — committed config can
#                       never widen its own pin.
#   VENDIR_CHECK_DESTINATIONS
#                       Override the pinned directories[] destination
#                       set (default: DIRSRC + the seven slice paths).
#   VENDIR_CHECK_DUALLIST_INCLUDE_ENTRY / _EXCLUDE_ENTRY
#                       Override the two destinations whose literal
#                       src/**/*.cpp|c lists duallist asserts must
#                       mirror (default: libbitcoinkernel includes what
#                       bitcoind excludes).
#
# All checks assert committed state (HEAD, not the working tree) — safe
# on a dirty tree, useless as a pre-commit hook; the maintainer's live
# preview is vendor-sync.sh + `git status`.
#
# Exit — the diff(1) contract: 0 every requested check passed, 1 any
# check reported drift (findings dominate: a proven mismatch outranks
# another check's couldn't-run), 2 no check found anything but at least
# one could not run (usage, missing tool, environment trouble).
# shellcheck disable=SC2329  # checks are invoked dynamically as "check_$c";
# the helpers are this file's shared library.
set -euo pipefail

# A git-hook environment exports GIT_* vars that silently retarget nested
# git calls at the outer repo (GIT_DIR/GIT_WORK_TREE win over -C). Every
# repo access below must see only $ROOT.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX \
    GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG_PARAMETERS
# Pin everything else a developer's config could skew, for every git call
# below *and* vendir's internal ones: literal pathspecs (a `*`/`:` in a
# managed path can never turn into magic), no opportunistic index writes
# (a read-only status on the live tree mustn't take index.lock mid-edit),
# real file modes, and no hooks — a global core.hooksPath (lefthook) would
# otherwise fire post-checkout inside the scratch worktree.
export GIT_LITERAL_PATHSPECS=1 GIT_OPTIONAL_LOCKS=0
# Never prompt for credentials — a renamed or deleted remote would
# otherwise hang ls-remote on a TTY — and abort a transfer that stalls
# below 1 KB/s for 30 s (BuildBuddy's documented CI defaults) instead of
# hanging until the job's own timeout.
export GIT_TERMINAL_PROMPT=0 GIT_HTTP_LOW_SPEED_LIMIT=1024 GIT_HTTP_LOW_SPEED_TIME=30
# Transport allowlist: https only, for every git call *and* vendir's own
# fetches — a committed url: could otherwise name file:/ssh:/ext: (ext::
# literally runs its payload as a command). `git bundle unbundle` is a
# local import — verified unaffected. Dedicated override var rather than
# honoring ambient GIT_ALLOW_PROTOCOL, which we treat as hostile env.
export GIT_ALLOW_PROTOCOL="${VENDIR_CHECK_ALLOW_PROTOCOLS:-https}"
export GIT_CONFIG_COUNT=6 \
    GIT_CONFIG_KEY_0=core.fileMode GIT_CONFIG_VALUE_0=true \
    GIT_CONFIG_KEY_1=core.hooksPath GIT_CONFIG_VALUE_1=/dev/null \
    GIT_CONFIG_KEY_2=core.autocrlf GIT_CONFIG_VALUE_2=false \
    GIT_CONFIG_KEY_3=core.fsmonitor GIT_CONFIG_VALUE_3=false \
    GIT_CONFIG_KEY_4=core.untrackedCache GIT_CONFIG_VALUE_4=false \
    GIT_CONFIG_KEY_5=core.excludesFile GIT_CONFIG_VALUE_5=/dev/null

# The pinned upstream identity — the one source this package vendors
# from, as literal word lists (word-split on use). check_allowlist
# asserts the committed config stays inside it; the fetching checks
# re-validate the values they contact against the same literals so a
# standalone `vendir-check.sh shadow` (or a bare run after an allowlist
# failure — main skips fetching checks then) can't be aimed at an
# arbitrary host or a non-checkout source dir by PR-controlled config.
UPSTREAM_URLS=${VENDIR_CHECK_UPSTREAM_URLS:-'https://github.com/bitcoin/bitcoin.git'}
UPSTREAM_DIRSRC=${VENDIR_CHECK_UPSTREAM_DIRSRC:-'.vendir-upstream/bitcoin'}

# The rest of the committed-shape pins: the full directories[] destination
# set (first slot IS the upstream checkout — it tracks DIRSRC) and the
# two entries whose literal src/** lists duallist asserts must mirror
# (kernel includes what the daemon excludes). Same env-seam contract:
# fixtures override, production runs take the defaults.
DESTINATIONS=${VENDIR_CHECK_DESTINATIONS:-"$UPSTREAM_DIRSRC Sources/crc32c Sources/leveldb Sources/minisketch Sources/secp256k1 Sources/libbitcoinkernel Sources/bitcoind Tests/BitcoinTests/Fixtures"}
DUALLIST_INC_ENTRY=${VENDIR_CHECK_DUALLIST_INCLUDE_ENTRY:-'Sources/libbitcoinkernel'}
DUALLIST_EXC_ENTRY=${VENDIR_CHECK_DUALLIST_EXCLUDE_ENTRY:-'Sources/bitcoind'}

# Same contract as die(), defined first — early-env failures still exit 2.
die0() { echo "error: $*" >&2; exit 2; }

command -v git >/dev/null 2>&1 \
    || die0 "required tool missing: git (xcode-select --install)"

# The stop-commands token for dump_untrusted — one per run, 96 bits
# from /dev/urandom. Generated here, not per dump: content can't learn
# a runtime token either way, and a failed read exits 2 at startup
# instead of misclassifying inside a check (a die inside a piped
# `printf | dump_untrusted` would only kill the pipe's subshell).
DUMP_TOKEN=vccheck-$(od -An -tx1 -N12 /dev/urandom 2>/dev/null | tr -d ' \n')
[ "${#DUMP_TOKEN}" -gt 12 ] \
    || die0 "dump token: /dev/urandom read failed"

if [ -n "${VENDIR_CHECK_ROOT:-}" ]; then
    ROOT=$(cd "$VENDIR_CHECK_ROOT" 2>/dev/null && pwd -P) \
        || die0 "VENDIR_CHECK_ROOT '$VENDIR_CHECK_ROOT' is not a directory"
else
    ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
fi
# The root must be the repo top level: a subdirectory would make worktree
# add check out the whole *outer* repo, and the check would read the outer
# vendir.yml — verifying the wrong tree without saying so.
# rev-parse first, on its own line: when it fails its empty output would
# make `cd ""` a no-op and the guard could pass by accident.
top=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null) \
    && [ -n "$top" ] \
    || die0 "'$ROOT' is not inside a git repository"
top=$(cd "$top" 2>/dev/null && pwd -P) \
    || die0 "cannot resolve repository top level under '$ROOT'"
[ "$top" = "$ROOT" ] \
    || die0 "VENDIR_CHECK_ROOT must be the repository top level ('$ROOT' is inside '$top')"
VENDIR_YML=$ROOT/vendir.yml
VENDIR=${VENDIR:-vendir}

# Environment/usage/internal trouble — exits 2 so a check that could not
# run never reads as "the tree is wrong" (exit 1 is findings only).
die() {
    echo "error: $*" >&2
    exit 2
}

# Emit an error line: a ::error:: annotation in CI, a plain line locally.
# Workflow-command data escapes % first, then CR/LF — the toolkit's
# escapeData order; `ref:`/`url:` text is PR-controlled, so never emit raw.
_err() {
    local msg=$*
    # Strip C0/DEL before anything else — untrusted url:/path values
    # flow through findings; a raw ESC/CSI/OSC fires on the maintainer's
    # terminal (and inside ::error:: data on the runner), and an
    # embedded newline could fake extra output lines.
    msg=$(printf '%s' "$msg" | LC_ALL=C tr -d '\000-\037\177')
    if [ "${GITHUB_ACTIONS:-}" = true ]; then
        msg=${msg//'%'/'%25'}
        printf '::error::%s\n' "$msg"
    else
        printf 'error: %s\n' "$msg" >&2
    fi
}
# A finding — the tree/config/lock disagree. Never exits: a check lists
# every mismatch it found before returning 1.
fail() { _err "$@"; }
# A check-execution problem inside a check (one entry's transport failed):
# reported the same way, but only drags the check to ERRORED (rc 2) when no
# entry reported drift — findings dominate within a check too.
cerr() { _err "$@"; }

# Status lines are advisory — after SIGHUP closes the terminal a stdout
# write fails, and a bare `note` under set -e would exit 1 (reads as
# drift). Status output can never be allowed to fail the gate.
note() {
    printf '%s\n' "$*" 2>/dev/null || :
}

# Every *value* read from the vendir files goes through explode(.) — a
# bare read would print a `*alias` literally if a YAML anchor is ever
# introduced (the sibling learned this the hard way). Key enumeration
# stays un-exploded so `<<:` merge keys surface (the allowlist check
# relies on it). Optional second arg reads a different file — the live
# files are the default; a check asserting committed state passes bytes
# or the worktree's file explicitly.
cfg() {
    yq "explode(.) | $1" "${2:-$VENDIR_YML}"
}

# Untrusted (PR-controlled) output, emitted inert on GitHub: both
# workflow-command parsers see nothing between the stop-commands
# markers. Indentation alone does NOT neutralize them — the runner
# TrimStart()s before matching `::`, and the legacy `##[` matcher fires
# anywhere in the line — so the markers are the only mechanism that
# covers both. On a local terminal the markers are noise lines but the
# escape strip still applies: untrusted bytes carry no C0 controls
# (ESC/CSI/OSC, CR line-overwrites), keeping tab and newline. Reads
# stdin, indents 4. The token is generated once at startup (see
# DUMP_TOKEN): a die inside this function would only kill the pipe's
# subshell and let the caller continue anyway.
dump_untrusted() {
    printf '%s\n' "::stop-commands::$DUMP_TOKEN" || :
    LC_ALL=C tr -d '\000-\010\013-\037\177' | sed 's/^/    /' || :
    printf '%s\n' "::$DUMP_TOKEN::" || :
}

# Each check's tool requirements — the dispatcher preflights the union of
# the requested set so a missing binary is one named error, not a cascade
# of command-not-found exits halfway through a long sync. One tool per
# line — a VENDIR path may contain spaces.
check_tools() {
    case "$1" in
        allowlist) printf '%s\n' git yq ;;
        resolve) printf '%s\n' git yq ;;
        duallist) printf '%s\n' git yq ;;
        shadow) printf '%s\n' git yq ;;
        sync) printf '%s\n' git yq "$VENDIR" ;;
        *) die "internal: no tool list for check '$1'" ;;
    esac
}

tool_hint() {
    case "$1" in
        *vendir*) echo "brew install carvel-dev/carvel/vendir (or point VENDIR at a binary)" ;;
        yq) echo "brew install yq" ;;
        git) echo "xcode-select --install" ;;
        *) echo "" ;;
    esac
}

# — checks ———————————————————————————————————————————————————————————
# Contract for check_* functions: the dispatcher runs each as a
# foreground subshell in *tested* context (`( check_$c ) || rc=$?`), so
# `set -e` is OFF inside — every step that must abort the check needs its
# own `|| die` or `|| { fail …; return 1; }`. Report findings via fail(),
# per-entry couldn't-verify problems via cerr(), `return 1` on findings,
# `return 2` when only errors occurred. die() mid-check still works (the
# subshell's exit 2 reads the same), and rc 0/1/2 are the whole contract —
# 3–127 means the check broke it (ERRORED, code printed), ≥128 is a signal
# and aborts the run. Signals: the parent records INT/TERM/HUP and exits
# with that code once the check returns; a terminal Ctrl-C reaches the
# whole group, and the subshell's own EXIT trap still cleans its worktree.

# Probe one node's shape, then enumerate its mapping keys against the
# level's allowed set — accumulating into the caller's found/errored
# locals via bash dynamic scope (the caller must declare them), and
# leaving the node's type tag in the caller's _KT so it can decide
# whether to descend. Shape semantics: absent (null) is skipped — the
# missing-field findings are other checks' territory; a present non-map
# node is a finding, not an error — the check ran and proved a violation.
# Keys are enumerated UN-exploded on purpose: explode(.) resolves `<<:`
# merge keys into their source's fields and hides them, while the literal
# `<<` is itself a foreign key. Repeated keys fail too — YAML 1.2 makes
# mapping keys a unique set, and parsers disagree on which duplicate wins
# (yamllint's key-duplicates rule), so the gate rejects rather than picks
# a side — the winner yq picks here is not necessarily the winner
# vendir's own parser picks. Keys are read by index and matched with `=`
# equality — a substring match would let a crafted key like `ref depth`
# borrow the boundary between two allowed names, and a line-oriented read
# would silently drop an empty-string key. Reads $cfg_yml through dynamic
# scope — the caller's local holds the committed bytes. Never exits;
# always returns 0.
keyscan() {
    local q=$1 label=$2 allowed=$3 nkeys i j k a ok
    local klist=()
    _KT=$(printf '%s' "$cfg_yml" | yq "$q | type" - 2>/dev/null) || _KT=
    case "$_KT" in
        '!!map') ;;
        '!!null') return 0 ;;
        '') cerr "$label — type probe failed (node skipped)"; errored=1; return 0 ;;
        *) fail "$label is a $_KT, not a mapping"; found=1; return 0 ;;
    esac
    nkeys=$(printf '%s' "$cfg_yml" | yq "$q | keys | length" -) \
        || { cerr "$label — key enumeration failed (node skipped)"; errored=1; return 0; }
    for ((i = 0; i < nkeys; i++)); do
        # Append in both paths — klist stays index-aligned for the dup
        # loop below even when a read fails (a failed read is cerr, not a
        # foreign-key finding: we couldn't see the key).
        if k=$(printf '%s' "$cfg_yml" | yq "$q | keys | .[$i]" -); then
            ok=0
            for a in $allowed; do  # word-split — the list is literals
                [ "$k" = "$a" ] && { ok=1; break; }
            done
            [ "$ok" = 1 ] \
                || { fail "$label — key '$k' is outside the allowed set ($allowed)"; found=1; }
        else
            cerr "$label — key read failed at index $i"; errored=1; k=''
        fi
        klist+=("$k")
    done
    # Repeated keys — pairwise because a key containing a newline would
    # garble a line-oriented uniq; n per level is tiny. An empty klist[i]
    # marks a failed read above — skipped, not a dup candidate (a real
    # empty-string key is already flagged foreign by the membership pass).
    for ((i = 0; i < nkeys; i++)); do
        [ -n "${klist[$i]}" ] || continue
        for ((j = 0; j < i; j++)); do
            if [ "${klist[$i]}" = "${klist[$j]}" ]; then
                fail "$label — key '${klist[$i]}' is repeated (duplicate keys are spec-invalid; which wins is parser-defined)"
                found=1
                break
            fi
        done
    done
    return 0
}

check_allowlist() {
    # Committed state, like resolve and sync — the gate asserts HEAD, not
    # the working tree.
    local cfg_yml found=0 errored=0 _KT
    cfg_yml=$(git -C "$ROOT" show HEAD:vendir.yml 2>/dev/null) \
        || die "HEAD has no vendir.yml (no commits yet?)"

    # Advisory — the verdict reads HEAD, so surface an unsynced local
    # edit rather than let it read as the checked state.
    local live_dirty
    live_dirty=$(git -C "$ROOT" status --porcelain --untracked-files=all -- vendir.yml || true)
    if [ -n "$live_dirty" ]; then
        note "note: uncommitted changes (allowlist checks HEAD, not the working tree):"
        printf '%s\n' "$live_dirty" | dump_untrusted
    fi

    # Unparseable committed YAML is couldn't-run — nothing exists to
    # enumerate; parseable-but-wrong-shaped nodes are findings below,
    # since the check ran and proved a violation.
    printf '%s' "$cfg_yml" | yq '.' - >/dev/null 2>&1 \
        || die "committed vendir.yml is malformed YAML"
    local t
    t=$(printf '%s' "$cfg_yml" | yq '. | type' -) \
        || die "type probe failed on committed vendir.yml's document root"
    [ "$t" = '!!map' ] \
        || { fail "vendir.yml's document root is a $t, not a mapping"; return 1; }
    keyscan '.' 'top level' 'apiVersion kind minimumRequiredVersion directories'

    # — pinned values that don't depend on directories: —
    # apiVersion/kind are the schema's identity, not data — a changed pair
    # silently redefines what every key below means.
    # A yq failure must classify couldn't-run (cerr), never read as a
    # wrong value and become a finding — same 1-vs-2 contract as every
    # other probe. `read-failed` is a sentinel, not config data.
    t=$(printf '%s' "$cfg_yml" | yq 'explode(.) | .apiVersion + " " + .kind' - 2>/dev/null) \
        || { cerr "apiVersion/kind read failed"; errored=1; t=read-failed; }
    case "$t" in
        'vendir.k14s.io/v1alpha1 Config' | read-failed) ;;
        *) fail "apiVersion/kind is '$t' — expected 'vendir.k14s.io/v1alpha1 Config'"; found=1 ;;
    esac
    # The version floor must exist — without it vendir never refuses an
    # older binary. Its value is not pinned here: the workflow pins the
    # binary, and a floor bump stays a two-file change.
    t=$(printf '%s' "$cfg_yml" | yq 'explode(.) | .minimumRequiredVersion' - 2>/dev/null) \
        || { cerr "minimumRequiredVersion read failed"; errored=1; t=read-failed; }
    case "$t" in
        '' | null) fail "minimumRequiredVersion is missing or empty — vendir's own version floor needs it"; found=1 ;;
        read-failed) ;;
    esac

    # Absent subject = couldn't-run (resolve reads it identically): a
    # missing, null, or empty directories: leaves nothing to enumerate,
    # and the per-directory pins below would just restate the same
    # absence as misleading per-path findings — so they're skipped too.
    # A present non-list directories: is a finding: definitively wrong,
    # and the shape probe proved it.
    local ndirs=0 dirs_ok=0
    t=$(printf '%s' "$cfg_yml" | yq '.directories | type' - 2>/dev/null) || t=
    case "$t" in
        '!!seq')
            if ndirs=$(printf '%s' "$cfg_yml" | yq '.directories | length' -); then
                if [ "$ndirs" -gt 0 ] 2>/dev/null; then
                    dirs_ok=1
                elif [ "$ndirs" = 0 ]; then
                    cerr "committed vendir.yml declares zero directories — nothing to scan"
                    errored=1
                else
                    cerr "committed vendir.yml — 'directories' length probe returned '$ndirs'"
                    errored=1
                fi
            else
                cerr "committed vendir.yml — 'directories' length probe failed"
                errored=1
            fi
            ;;
        '!!null') cerr "committed vendir.yml declares no 'directories' list — nothing to scan"; errored=1 ;;
        '') cerr "committed vendir.yml — 'directories' type probe failed"; errored=1 ;;
        *) fail "committed vendir.yml's directories is a $t, not a list"; found=1 ;;
    esac
    [ "$dirs_ok" = 1 ] || {
        ((found)) && return 1
        return 2
    }

    # Per-node scans. Structure queries (type/length/keys) stay un-exploded
    # — the raw document is what key-conflicts hide in; value reads
    # (path/url) go through explode(.) per the file's convention.
    local all_dir='path contents'
    local all_contents='path git directory includePaths excludePaths legalPaths ignorePaths newRootPath'
    local all_git='url ref depth skipInitSubmodules'
    local all_direntry='path'
    local allowed_urls=$UPSTREAM_URLS
    local allowed_dirsrc=$UPSTREAM_DIRSRC
    local dirpaths=() i j ncontents cpath ctype dpath dlabel url ok u
    local has_git has_dir srcdir
    for ((i = 0; i < ndirs; i++)); do
        dlabel="directories[$i]"
        keyscan ".directories[$i]" "$dlabel" "$all_dir"
        [ "$_KT" = '!!map' ] || continue
        dpath=$(printf '%s' "$cfg_yml" | yq "explode(.) | .directories[$i].path" -) \
            || { cerr "$dlabel — path read failed (entry skipped)"; errored=1; continue; }
        case "$dpath" in
            '' | null) fail "$dlabel has no usable path value"; found=1 ;;
            *) dirpaths+=("$dpath"); dlabel="'$dpath'" ;;
        esac

        ctype=$(printf '%s' "$cfg_yml" | yq ".directories[$i].contents | type" - 2>/dev/null) || ctype=
        ncontents=0
        case "$ctype" in
            '!!seq')
                ncontents=$(printf '%s' "$cfg_yml" | yq ".directories[$i].contents | length" -) \
                    || { cerr "$dlabel — contents length probe failed (entry skipped)"; errored=1; continue; }
                ;;
            '!!null') ;;  # absent — the count below reports it
            '') cerr "$dlabel — contents type probe failed (entry skipped)"; errored=1; continue ;;
            *) fail "$dlabel contents is a $ctype, not a list"; found=1; continue ;;
        esac
        [ "$ncontents" = 1 ] \
            || { fail "$dlabel — $ncontents contents entries; exactly one contents per directory"; found=1; }
        for ((j = 0; j < ncontents; j++)); do
            keyscan ".directories[$i].contents[$j]" "$dlabel contents[$j]" "$all_contents"
            [ "$_KT" = '!!map' ] || continue
            cpath=$(printf '%s' "$cfg_yml" | yq "explode(.) | .directories[$i].contents[$j].path" -) \
                || { cerr "$dlabel contents[$j] — path read failed"; errored=1; continue; }
            [ "$cpath" = '.' ] \
                || { fail "$dlabel contents[$j].path is '$cpath', not '.' — a contents entry must own its destination root"; found=1; }

            # Source polarity — the single-fetch shape (ADR 0011):
            # exactly one source key per entry, the git: checkout is
            # directories[0] at UPSTREAM_DIRSRC (vendir syncs
            # directories in config order; the slices below copy it), and
            # every other entry is a directory: slice of that checkout.
            # A failed probe must report couldn't-run (cerr), not fall
            # into the `*)` neither-key arm below and read as a finding.
            has_git=$(printf '%s' "$cfg_yml" | yq "explode(.) | .directories[$i].contents[$j] | has(\"git\")" - 2>/dev/null) \
                || { cerr "$dlabel contents[$j] — git-key probe failed"; errored=1; continue; }
            has_dir=$(printf '%s' "$cfg_yml" | yq "explode(.) | .directories[$i].contents[$j] | has(\"directory\")" - 2>/dev/null) \
                || { cerr "$dlabel contents[$j] — directory-key probe failed"; errored=1; continue; }
            case "$has_git:$has_dir" in
                true:false | false:true) ;;
                true:true) fail "$dlabel contents[$j] declares both git: and directory: — exactly one source key per entry"; found=1 ;;
                *) fail "$dlabel contents[$j] declares neither git: nor directory: — exactly one source key per entry"; found=1 ;;
            esac
            keyscan ".directories[$i].contents[$j].git" "$dlabel contents[$j].git" "$all_git"
            keyscan ".directories[$i].contents[$j].directory" "$dlabel contents[$j].directory" "$all_direntry"
            if [ "$has_git" = true ]; then
                if [ "$dpath" != "$UPSTREAM_DIRSRC" ] || [ "$i" -ne 0 ]; then
                    fail "$dlabel contents[$j] is a git: fetch outside directories[0] — the single-checkout shape puts the only network fetch first at $UPSTREAM_DIRSRC"
                    found=1
                fi
                url=$(printf '%s' "$cfg_yml" | yq "explode(.) | .directories[$i].contents[$j].git.url" -) \
                    || { cerr "$dlabel contents[$j].git — url read failed"; errored=1; continue; }
                case "$url" in
                    '' | null) ;;  # absent url: — resolve names the missing field
                    *)
                        ok=0
                        for u in $allowed_urls; do
                            [ "$url" = "$u" ] && { ok=1; break; }
                        done
                        [ "$ok" = 1 ] \
                            || { fail "$dlabel — git.url '$url' is outside the declared upstream ($allowed_urls)"; found=1; }
                        ;;
                esac
            fi
            # Inverse polarity too: the git: checkout isn't just confined
            # to directories[0], it is REQUIRED there — an all-directory:
            # config has no upstream fetch at all and fails every other
            # check only accidentally (resolve dies couldn't-run, not a
            # named finding).
            if [ "$i" -eq 0 ] && [ "$j" -eq 0 ] && [ "$has_git" != true ]; then
                fail "directories[0].contents[0] is not the git: checkout — the single-fetch shape (ADR 0011) puts the only network fetch first at $UPSTREAM_DIRSRC"
                found=1
            fi
            if [ "$has_dir" = true ]; then
                # A failed read must not read as an absent path — that
                # arm silently skips the dirsrc pin (fail-open).
                srcdir=$(printf '%s' "$cfg_yml" | yq "explode(.) | .directories[$i].contents[$j].directory.path" - 2>/dev/null) \
                    || { cerr "$dlabel contents[$j] — directory.path read failed"; errored=1; continue; }
                case "$srcdir" in
                    '' | null) ;;  # absent path — other checks name it
                    *)
                        ok=0
                        for u in $allowed_dirsrc; do
                            [ "$srcdir" = "$u" ] && { ok=1; break; }
                        done
                        [ "$ok" = 1 ] \
                            || { fail "$dlabel — directory.path '$srcdir' repoints the slice source — only $UPSTREAM_DIRSRC holds upstream bytes"; found=1; }
                        ;;
                esac
            fi
        done
    done

    # Destination set — `=` equality in both directions. Counting
    # occurrences also catches a duplicated destination, which a
    # sort|comm diff would only show as an unexplained surplus.
    local expected_paths=$DESTINATIONS
    local ep seen
    for t in ${dirpaths[@]+"${dirpaths[@]}"}; do
        ok=0
        for ep in $expected_paths; do
            [ "$t" = "$ep" ] && { ok=1; break; }
        done
        [ "$ok" = 1 ] \
            || { fail "unexpected directories[].path '$t' — outside the eight declared destinations"; found=1; }
    done
    for ep in $expected_paths; do
        seen=0
        for t in ${dirpaths[@]+"${dirpaths[@]}"}; do
            [ "$t" = "$ep" ] && seen=$((seen + 1))
        done
        case "$seen" in
            1) ;;
            0) fail "declared destination '$ep' has no directories[] entry"; found=1 ;;
            *) fail "declared destination '$ep' appears in $seen directories[] entries"; found=1 ;;
        esac
    done
    ((found)) && return 1
    ((errored)) && return 2
    return 0
}

# Resolve a vendir git ref to its upstream commit SHA. A 40-hex ref
# resolves to itself — ls-remote lists refs, not raw SHAs. Otherwise
# query refs/tags/<ref> plus its ^{} peel: the peeled line wins, because
# an annotated tag's bare ref line is the tag-*object* SHA and would
# false-fail the lock comparison. Branch names and `origin/…` refs match
# nothing under refs/tags/ — empty output fails the check.
# Prints the SHA; returns 2 on transport failure, 3 when nothing
# resolved.
resolve_ref() {
    local url=$1 ref=$2 out sha refname tag="" peel=""
    # grep, not [[ =~ ]] — bash 3.2's regex engine mishandles {N}
    # intervals. Uppercase hex is a valid commit-ish; normalize so it
    # compares equal to the lock's lowercase sha.
    if printf '%s' "$ref" | grep -qiE '^[0-9a-f]{40}$'; then
        printf '%s' "$ref" | tr '[:upper:]' '[:lower:]'
        return 0
    fi
    # `--` is load-bearing: a url: starting with '-' would otherwise be
    # parsed as an option (--upload-pack runs a command — CVE-2017-1000117
    # class). GIT_ALLOW_PROTOCOL is the second layer, in the env block.
    # `-C /` pins the probe to the same config layer preflight's rewrite
    # audit and vendir's temp-repo fetches see (system+global+env) — never
    # the caller's cwd repo, whose local rules nobody else consults.
    # stderr is dropped like every other untrusted-arg call: git quotes
    # the url verbatim in fatal lines, and config text must never reach
    # the log raw — the caller's cerr reports via the escaped channel.
    out=$(git -C / ls-remote -- "$url" "refs/tags/$ref" "refs/tags/$ref^{}" \
        2>/dev/null) || return 2
    while read -r sha refname; do
        case "$refname" in
            "refs/tags/$ref") tag=$sha ;;
            "refs/tags/$ref^{}") peel=$sha ;;
        esac
    done <<EOF
$out
EOF
    [ -n "${peel:-$tag}" ] || return 3
    printf '%s' "${peel:-$tag}"
}

check_resolve() {
    # Committed state, like the sync — both files come out of HEAD so an
    # uncommitted edit can't move the goalposts.
    local cfg_yml lock_yml
    cfg_yml=$(git -C "$ROOT" show HEAD:vendir.yml 2>/dev/null) \
        || die "HEAD has no vendir.yml (no commits yet?)"
    lock_yml=$(git -C "$ROOT" show HEAD:vendir.lock.yml 2>/dev/null) \
        || die "HEAD has no vendir.lock.yml"

    # Shape check before parsing: a malformed file yields an empty
    # directory list downstream, which the guards there would misreport
    # as "declares no directories".
    printf '%s' "$cfg_yml" | yq 'explode(.) | has("directories") == true' - | grep -qx true \
        || die "committed vendir.yml is malformed YAML or lacks a 'directories' list"
    printf '%s' "$lock_yml" | yq 'explode(.) | has("directories") == true' - | grep -qx true \
        || die "committed vendir.lock.yml is malformed YAML or lacks a 'directories' list"

    # Advisory: the check asserts committed bytes — without this a local
    # "did my ref: bump take?" run silently passes against the old HEAD.
    local live_dirty
    live_dirty=$(git -C "$ROOT" status --porcelain --untracked-files=all -- vendir.yml vendir.lock.yml || true)
    if [ -n "$live_dirty" ]; then
        note "note: uncommitted changes (resolve checks HEAD, not the working tree):"
        printf '%s\n' "$live_dirty" | dump_untrusted
    fi

    # Only git:-bearing entries resolve — directory: slices copy local
    # bytes and have nothing to fetch. `.contents[0].git | type` filters
    # them out without materializing a null row.
    local dirs=() urls=() refs=() counts=() lockpaths=() lockshas=()
    local line rest path url ref ncontents sha i j u resolved rc
    # Manual field splits — `IFS=tab read` would collapse an empty middle
    # field into a misaligned row.
    # [ -n ] guards: yq emits a blank line for a no-match select, which
    # must not phantom up as an empty row.
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        path=${line%%$'\t'*}; rest=${line#*$'\t'}
        url=${rest%%$'\t'*}; rest=${rest#*$'\t'}
        ref=${rest%%$'\t'*}; ncontents=${rest##*$'\t'}
        dirs+=("$path"); urls+=("$url"); refs+=("$ref"); counts+=("$ncontents")
    done < <(printf '%s' "$cfg_yml" | yq 'explode(.) | .directories[] | select(.contents[0].git | type == "!!map") | [.path, .contents[0].git.url, .contents[0].git.ref, (.contents | length)] | @tsv' -)
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        lockpaths+=("${line%%$'\t'*}"); lockshas+=("${line##*$'\t'}")
    done < <(printf '%s' "$lock_yml" | yq 'explode(.) | .directories[] | [.path, .contents[0].git.sha] | @tsv' -)
    ((${#dirs[@]})) || die "committed vendir.yml declares no git: contents — nothing resolves (a directory-only config is an allowlist finding, not resolve's subject)"

    local found=0 errored=0
    for i in "${!dirs[@]}"; do
        path=${dirs[$i]}; url=${urls[$i]}; ref=${refs[$i]}
        # Shape guard first — a directory with !=1 contents entries is
        # something this check can't fully see (allowlist asserts exactly
        # one per directory); failing named beats a silent skip.
        case "${counts[$i]}" in
            1) ;;
            *) fail "$path — ${counts[$i]} contents entries; resolve covers exactly one per directory (allowlist asserts the same)"; found=1; continue ;;
        esac
        # Standalone runs re-validate the host they contact — a named
        # `vendir-check.sh resolve` skips allowlist, so the pinned set
        # is re-asserted per url here rather than trusted.
        for u in $UPSTREAM_URLS; do  # word-split — literals
            [ "$u" = "$url" ] && break
        done
        [ "$u" = "$url" ] \
            || { fail "$path — git.url '$url' is outside the declared upstream ($UPSTREAM_URLS)"; found=1; continue; }
        sha=""
        if ((${#lockpaths[@]})); then
            for j in "${!lockpaths[@]}"; do
                if [ "${lockpaths[$j]}" = "$path" ]; then sha=${lockshas[$j]}; break; fi
            done
        fi
        case "$sha" in
            "" | null) fail "$path — no contents[0].git.sha in the lock"; found=1; continue ;;
        esac
        case "$url" in
            "" | null) fail "$path — no contents[0].git.url in the config (non-git contents?)"; found=1; continue ;;
        esac
        resolved=""; rc=0
        resolved=$(resolve_ref "$url" "$ref") || rc=$?  # || keeps set -e off it
        case $rc in
            0) ;;
            2) cerr "$path — git ls-remote failed for $url (network or auth trouble) — entry not verified"
               errored=1; continue ;;
            *) fail "$path — ref '$ref' resolves to nothing at $url (tags only; a branch name queries nothing under refs/tags/)"
               found=1; continue ;;
        esac
        printf '%s' "$resolved" | grep -qE '^[0-9a-f]{40}$' \
            || { fail "$path — resolved value '$resolved' is not a full SHA"; found=1; continue; }
        [ "$resolved" = "$sha" ] \
            || { fail "$path — ref '$ref' resolves to $resolved upstream; lock holds $sha — a ref edit without re-sync, or a moved tag"; found=1; }
    done
    # Findings dominate *within* a check too: proven drift outranks
    # another entry's transport failure.
    ((found)) && return 1
    ((errored)) && return 2
    return 0
}

check_duallist() {
    # Committed state — the gate asserts HEAD.
    local cfg_yml
    cfg_yml=$(git -C "$ROOT" show HEAD:vendir.yml 2>/dev/null) \
        || die "HEAD has no vendir.yml (no commits yet?)"
    printf '%s' "$cfg_yml" | yq 'explode(.) | has("directories") == true' - | grep -qx true \
        || die "committed vendir.yml is malformed YAML or lacks a 'directories' list"

    local live_dirty
    live_dirty=$(git -C "$ROOT" status --porcelain --untracked-files=all -- vendir.yml || true)
    if [ -n "$live_dirty" ]; then
        note "note: uncommitted changes (duallist checks HEAD, not the working tree):"
        printf '%s\n' "$live_dirty" | dump_untrusted
    fi

    local found=0 errored=0
    local kcount bcount kinc bexc
    kcount=$(printf '%s' "$cfg_yml" | yq "explode(.) | [.directories[] | select(.path == \"$DUALLIST_INC_ENTRY\")] | length" - 2>/dev/null) || kcount=
    bcount=$(printf '%s' "$cfg_yml" | yq "explode(.) | [.directories[] | select(.path == \"$DUALLIST_EXC_ENTRY\")] | length" - 2>/dev/null) || bcount=
    [ "$kcount" = 1 ] \
        || { cerr "directories[] entry '$DUALLIST_INC_ENTRY' found $kcount times — can't locate the include list"; errored=1; }
    [ "$bcount" = 1 ] \
        || { cerr "directories[] entry '$DUALLIST_EXC_ENTRY' found $bcount times — can't locate the exclude list"; errored=1; }
    ((errored)) && return 2

    # The dual invariant: the exclude-side entry extracts every
    # src/**/*.cpp|.c via globs, then re-excludes the kernel's
    # translation units literally — so the include side's literal list
    # and the exclude side's literal list must be the same set.
    # "Literal" means no pattern chars (vendir treats every entry as a
    # doublestar pattern) and scoped to src/** translation units — the
    # `.h` globs, licenses, and the `**/bitcoin.cpp`-style tool
    # exclusions all sit outside it.
    kinc=$(printf '%s' "$cfg_yml" | yq "explode(.) | .directories[] | select(.path == \"$DUALLIST_INC_ENTRY\") | .contents[].includePaths[]?" -) \
        || { cerr "$DUALLIST_INC_ENTRY includePaths read failed"; return 2; }
    bexc=$(printf '%s' "$cfg_yml" | yq "explode(.) | .directories[] | select(.path == \"$DUALLIST_EXC_ENTRY\") | .contents[].excludePaths[]?" -) \
        || { cerr "$DUALLIST_EXC_ENTRY excludePaths read failed"; return 2; }
    local s1 s2 only_inc only_exc
    s1=$(printf '%s\n' "$kinc" | grep -E '^src/.*\.(cpp|c)$' | grep -vE '[][?*{}\\]' | sort -u) || :
    s2=$(printf '%s\n' "$bexc" | grep -E '^src/.*\.(cpp|c)$' | grep -vE '[][?*{}\\]' | sort -u) || :
    # Both sides empty reads as "nothing to compare" — a rename of either
    # destination's list would silently vacate the invariant, so an empty
    # pair is couldn't-verify, never a pass.
    if [ -z "$s1" ] && [ -z "$s2" ]; then
        cerr "no literal src/**/*.cpp|.c entries on either side — the dual lists look renamed or emptied; nothing to compare"
        return 2
    fi
    only_inc=$(comm -23 <(printf '%s\n' "$s1") <(printf '%s\n' "$s2")) || :
    only_exc=$(comm -13 <(printf '%s\n' "$s1") <(printf '%s\n' "$s2")) || :
    if [ -n "$only_inc" ]; then
        while IFS= read -r line; do
            fail "$line — in $DUALLIST_INC_ENTRY includePaths but not $DUALLIST_EXC_ENTRY excludePaths — the translation unit lands in BOTH targets (duplicate symbols at link time)"
        done <<< "$only_inc"
        found=1
    fi
    if [ -n "$only_exc" ]; then
        while IFS= read -r line; do
            fail "$line — in $DUALLIST_EXC_ENTRY excludePaths but not $DUALLIST_INC_ENTRY includePaths — the translation unit lands in NEITHER target (silently dropped source)"
        done <<< "$only_exc"
        found=1
    fi
    ((found)) && return 1
    return 0
}

# Can $1 be probed as a literal path under a commit? Two failure tiers so
# the caller keeps distinct causes:
#   1  a doublestar glob char or URL-hostile byte — vendir treats
#      ignorePaths entries as patterns (isPathIgnored, staging_dir.go),
#      so a glob reaches upstream paths no single ls-tree does; a ? #
#      space or % can never be trusted to map one-to-one either.
#   2  not a clean relative path — ./ and ../ segments would probe a
#      different path than vendir would ever match, and a leading or
#      trailing slash or empty segment collapses the same way.
# Empty/null lands in tier 2: callers that name the case check it first.
probeable_path() {
    case "$1" in "" | null) return 2 ;; esac
    # (No \n in the banned list: $(printf '\n') strips to empty in $(),
    # and line-oriented grep can't match a newline inside a line anyway —
    # a value containing one is split before this function sees it, which
    # is why the ignorePaths CR/LF probe runs at the yq level.)
    if printf '%s' "$1" | grep -qF -e '*' -e '?' -e '[' -e '{' -e "\\" \
        || printf '%s' "$1" | grep -qF -e '#' -e ' ' -e '%' -e '"' \
            -e '<' -e '>' -e '|' -e '^' -e '`' -e ']' -e '}' \
            -e "$(printf '\t')" -e "$(printf '\r')"; then
        return 1
    fi
    case "$1" in
        /* | */ | */../* | ../* | */.. | .. | ./* | . | */./* | */. | *//*) return 2 ;;
    esac
    return 0
}

check_shadow() {
    # Committed state — both files out of HEAD.
    local cfg_yml lock_yml
    # Suppress partial-clone lazy fetch: the probe must answer from local
    # objects or not at all — a missing object is couldn't-verify, never a
    # silent network fetch mid-check. Inert on gits that don't know it.
    export GIT_NO_LAZY_FETCH=1
    cfg_yml=$(git -C "$ROOT" show HEAD:vendir.yml 2>/dev/null) \
        || die "HEAD has no vendir.yml (no commits yet?)"
    lock_yml=$(git -C "$ROOT" show HEAD:vendir.lock.yml 2>/dev/null) \
        || die "HEAD has no vendir.lock.yml"

    printf '%s' "$cfg_yml" | yq 'explode(.) | has("directories") == true' - | grep -qx true \
        || die "committed vendir.yml is malformed YAML or lacks a 'directories' list"
    printf '%s' "$lock_yml" | yq 'explode(.) | has("directories") == true' - | grep -qx true \
        || die "committed vendir.lock.yml is malformed YAML or lacks a 'directories' list"

    local live_dirty
    live_dirty=$(git -C "$ROOT" status --porcelain --untracked-files=all -- vendir.yml vendir.lock.yml || true)
    if [ -n "$live_dirty" ]; then
        note "note: uncommitted changes (shadow checks HEAD, not the working tree):"
        printf '%s\n' "$live_dirty" | dump_untrusted
    fi

    # Per-directory row: path, contents count, contents[0].path,
    # has-git/has-directory booleans (classified in bash — yq's `if`
    # only exists in v4.54.1+), directory.path (slice source),
    # newRootPath, git.url. The probe space for an entry is the source
    # dir's (url, locked-sha) — for the git: entry itself and for every
    # slice that copies it.
    local dirs=() counts=() cpaths=() kinds=() srcdirs=() nrps=() urls=()
    local lockpaths=() lockshas=()
    local line rest path ncontents cpath hasg hasd kind srcdir nrp url sha i j
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        path=${line%%$'\t'*}; rest=${line#*$'\t'}
        ncontents=${rest%%$'\t'*}; rest=${rest#*$'\t'}
        cpath=${rest%%$'\t'*}; rest=${rest#*$'\t'}
        hasg=${rest%%$'\t'*}; rest=${rest#*$'\t'}
        hasd=${rest%%$'\t'*}; rest=${rest#*$'\t'}
        srcdir=${rest%%$'\t'*}; rest=${rest#*$'\t'}
        nrp=${rest%%$'\t'*}; url=${rest##*$'\t'}
        # git wins on the malformed both-kinds case (allowlist flags it)
        kind=none; case $hasg/$hasd in
            true/*) kind=git ;;
            */true) kind=directory ;;
        esac
        dirs+=("$path"); counts+=("$ncontents"); cpaths+=("$cpath")
        kinds+=("$kind"); srcdirs+=("$srcdir"); nrps+=("$nrp"); urls+=("$url")
    done < <(printf '%s' "$cfg_yml" | yq 'explode(.) | .directories[] | [.path, (.contents | length), .contents[0].path, (.contents[0] | has("git")), (.contents[0] | has("directory")), .contents[0].directory.path, .contents[0].newRootPath, .contents[0].git.url] | @tsv' -)
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        lockpaths+=("${line%%$'\t'*}"); lockshas+=("${line##*$'\t'}")
    done < <(printf '%s' "$lock_yml" | yq 'explode(.) | .directories[] | [.path, .contents[0].git.sha] | @tsv' -)
    ((${#dirs[@]})) || die "committed vendir.yml declares no directories"

    # Object-store memo, keyed by "path<TAB>sha": the first probe for a
    # probe space resolves where the locked tree is readable — the live
    # checkout's object store when it already holds the SHA (read-only;
    # GIT_NO_LAZY_FETCH keeps a promisor clone from stalling a network
    # fetch mid-check), else a scratch bare repo filled by one
    # depth-1 blob:none fetch. Bash 3.2: parallel arrays. The result is
    # returned through dynamic scope (STORE_OUT), not $( ) — a command
    # substitution would fork a subshell and the memo would die with it.
    local sp_keys=() sp_stores=() sp_rcs=()
    local wt="" STORE_OUT STORE_RC srcfound
    make_store() {
        # $1 = dir path holding the checkout, $2 = sha, $3 = url.
        local key k live out spdir
        key="$1"$'\t'"$2"
        for k in "${!sp_keys[@]}"; do
            if [ "${sp_keys[$k]}" = "$key" ]; then
                STORE_OUT=${sp_stores[$k]}
                return "${sp_rcs[$k]}"
            fi
        done
        STORE_OUT=""
        # Live cache first — a read-only look at the checkout's objects;
        # the patched working tree never enters the answer. cat-file
        # proves the commit is local; a non-empty root ls-tree proves its
        # trees readable — together they anchor the probe space.
        live=$ROOT/$1
        if [ -d "$live/.git" ] \
            && git -C "$live" cat-file -e "$2" 2>/dev/null \
            && out=$(git -C "$live" ls-tree "$2" 2>/dev/null) \
            && [ -n "$out" ]; then
            sp_keys+=("$key"); sp_stores+=("$live"); sp_rcs+=(0)
            STORE_OUT=$live
            return 0
        fi
        # Scratch: init a bare repo and depth-1 blob:none fetch the SHA —
        # ~200 KB, and the fetch succeeding IS the anchor (a dead pin
        # can't silently produce all-absent answers).
        if [ -z "$wt" ]; then
            wt=$(mktemp -d "${TMPDIR:-/tmp}/vendir-check-shadow.XXXXXX") || return 2
            # Same contract as check_sync's trap: a Ctrl-C kills the
            # check subshell and bash still runs its EXIT trap — scratch
            # stores must not leak on interrupt (CI's only shadow path).
            # shellcheck disable=SC2064
            trap "rm -rf $(printf '%q' "$wt")" EXIT
        fi
        spdir=$wt/store-${#sp_keys[@]}
        if git init --bare -q "$spdir" 2>/dev/null \
            && git -C "$spdir" fetch -q --depth 1 --filter=blob:none -- "$3" "$2" 2>/dev/null \
            && git -C "$spdir" cat-file -e "$2" 2>/dev/null \
            && out=$(git -C "$spdir" ls-tree "$2" 2>/dev/null) && [ -n "$out" ]; then
            sp_keys+=("$key"); sp_stores+=("$spdir"); sp_rcs+=(0)
            STORE_OUT=$spdir
            return 0
        fi
        sp_keys+=("$key"); sp_stores+=(""); sp_rcs+=(2)
        return 2
    }

    local found=0 errored=0
    local itype ip rc prefix lt ltype srckind srcpath srcurl srcsha raw_ip nl_ip dead u
    local tag_ip tip badtype
    local entries=() toprobe=() deads=() store probe out
    for i in "${!dirs[@]}"; do
        path=${dirs[$i]}
        case "${counts[$i]}" in
            1) ;;
            *) fail "$path — ${counts[$i]} contents entries; shadow covers exactly one per directory (allowlist asserts the same)"; found=1; continue ;;
        esac
        case "${cpaths[$i]}" in
            .) ;;
            "" | null) fail "$path — no contents[0].path in the config"; found=1; continue ;;
            *) cerr "$path — contents[0].path is '${cpaths[$i]}', not '.' — entries under a contents subdir can't be mapped to an upstream path"; errored=1; continue ;;
        esac

        # Resolve the probe space: which upstream (url, sha) can shadow
        # this destination's preserved files. A git: entry IS the space;
        # a directory: slice borrows the space of the checkout it copies.
        srckind=${kinds[$i]}; srcpath=""; srcurl=""; srcsha=""
        case "$srckind" in
            git)
                srcpath=$path; srcurl=${urls[$i]} ;;
            directory)
                srcpath=${srcdirs[$i]}
                case "$srcpath" in
                    "" | null) fail "$path — directory: slice with no directory.path"; found=1; continue ;;
                esac
                srcfound=0
                for j in "${!dirs[@]}"; do
                    [ "${dirs[$j]}" = "$srcpath" ] || continue
                    srcfound=1
                    [ "${kinds[$j]}" = git ] && srcurl=${urls[$j]}
                done
                if [ "$srcfound" = 0 ]; then
                    cerr "$path — slice source '$srcpath' not found among directories[]"; errored=1; continue
                fi
                # The slice must copy the declared checkout — a bare run
                # asserts it via allowlist, but a standalone `shadow`
                # re-pins it here like the url below (plan: every
                # fetching check re-validates what it contacts).
                for u in $UPSTREAM_DIRSRC; do  # word-split — literals
                    [ "$u" = "$srcpath" ] && break
                done
                [ "$u" = "$srcpath" ] \
                    || { fail "$path — slice source '$srcpath' is outside the declared upstream checkout ($UPSTREAM_DIRSRC)"; found=1; continue; }
                case "$srcurl" in
                    "" | null) cerr "$path — slice source '$srcpath' has no git: contents to probe"; errored=1; continue ;;
                esac
                ;;
            *) fail "$path — contents[0] declares neither git: nor directory: (allowlist asserts one)"; found=1; continue ;;
        esac
        # srcpath feeds a filesystem lookup ($ROOT/$srcpath) — it must be
        # a clean relative path or a crafted directory.path could aim the
        # object-store probe outside the repo.
        rc=0; probeable_path "$srcpath" || rc=$?
        [ "$rc" = 0 ] \
            || { cerr "$path — source path '$srcpath' isn't a clean relative path"; errored=1; continue; }
        for j in "${!lockpaths[@]}"; do
            if [ "${lockpaths[$j]}" = "$srcpath" ]; then srcsha=${lockshas[$j]}; break; fi
        done
        case "$srcsha" in
            "" | null) fail "$path — no git.sha in the lock for source '$srcpath'"; found=1; continue ;;
        esac
        # The lock's sha lands in git's option position (cat-file,
        # ls-tree) — a `-`-leading or otherwise malformed value would
        # parse as flags. It fails closed anyway (a probe error is
        # cerr), but the explicit check names the real cause.
        printf '%s' "$srcsha" | grep -qE '^[0-9a-fA-F]{40}$' \
            || { cerr "$path — locked sha '$srcsha' for '$srcpath' isn't a 40-hex commit id"; errored=1; continue; }
        case "$srcurl" in
            "" | null) fail "$path — no git.url for source '$srcpath'"; found=1; continue ;;
            -*) cerr "$path — source url '$srcurl' starts with '-' (could parse as a git option)"; errored=1; continue ;;
        esac
        # Standalone runs re-validate the host they contact — a named
        # `vendir-check.sh shadow` skips allowlist, so the pinned set
        # is re-asserted per resolved source url here.
        for u in $UPSTREAM_URLS; do  # word-split — literals
            [ "$u" = "$srcurl" ] && break
        done
        [ "$u" = "$srcurl" ] \
            || { fail "$path — source git.url '$srcurl' is outside the declared upstream ($UPSTREAM_URLS)"; found=1; continue; }

        # newRootPath re-roots the copied tree BEFORE ignorePaths match —
        # the upstream coordinate of a destination-relative entry is
        # <newRootPath>/<entry>. Validate it like an entry: a pattern or
        # an unclean path can't form an honest probe.
        prefix=""
        case "${nrps[$i]}" in
            "" | null) ;;
            *)
                rc=0; probeable_path "${nrps[$i]}" || rc=$?
                case "$rc" in
                    0) prefix=${nrps[$i]}/ ;;
                    1) cerr "$path — newRootPath '${nrps[$i]}' is a pattern; can't form a probe path"; errored=1; continue ;;
                    *) cerr "$path — newRootPath '${nrps[$i]}' isn't a clean relative path"; errored=1; continue ;;
                esac
                ;;
        esac

        # Shape guard before enumerating — a present non-list ignorePaths
        # is a proven violation; absent (null) is the common case.
        itype=$(printf '%s' "$cfg_yml" | yq "explode(.) | .directories[$i].contents[0].ignorePaths | type" - 2>/dev/null) || itype=
        case "$itype" in
            '!!null') continue ;;
            '!!seq') ;;
            '') cerr "$path — ignorePaths type probe failed (entry skipped)"; errored=1; continue ;;
            *) fail "$path — contents[0].ignorePaths is a $itype, not a list"; found=1; continue ;;
        esac

        # Entries must be strings — a scalar like `123` enumerates as
        # the literal `123`, passes probeable_path, and greens a config
        # vendir's own parser would reject. tag() reports each node's
        # YAML type.
        tag_ip=$(printf '%s' "$cfg_yml" | yq "explode(.) | .directories[$i].contents[0].ignorePaths[]? | tag" -) \
            || { cerr "$path — ignorePaths entry-type probe failed (entry skipped)"; errored=1; continue; }
        badtype=0
        while IFS= read -r tip; do
            case "$tip" in
                '!!str') ;;
                *) fail "$path — ignorePaths entry is a $tip, not a string"; found=1; badtype=1 ;;
            esac
        done <<< "$tag_ip"
        [ "$badtype" = 0 ] || continue

        # Capture before splitting — a yq failure must report couldn't-
        # verify, not read as an empty list and green the directory. A
        # CR/LF-bearing entry would split into fragments the line reader
        # can't distinguish from real paths; refuse it as unverifiable
        # rather than probe a misparsed name. (The CR/LF probe runs at
        # the yq level because the newline is invisible after splitting.)
        raw_ip=$(printf '%s' "$cfg_yml" | yq "explode(.) | .directories[$i].contents[0].ignorePaths[]?" -) \
            || { cerr "$path — ignorePaths enumeration failed (entry skipped)"; errored=1; continue; }
        nl_ip=$(printf '%s' "$cfg_yml" | yq "explode(.) | .directories[$i].contents[0].ignorePaths[]? | select(test(\"[\\n\\r]\"))" - 2>/dev/null) \
            || { cerr "$path — ignorePaths CR/LF probe failed (entry skipped)"; errored=1; continue; }
        [ -z "$nl_ip" ] \
            || { cerr "$path — ignorePaths entry contains CR/LF — can't probe unambiguously"; errored=1; continue; }
        entries=(); toprobe=(); deads=()
        while IFS= read -r ip; do
            [ -n "$ip" ] || continue
            entries+=("$ip")
        done <<< "$raw_ip"
        ((${#entries[@]})) || continue
        for ip in "${entries[@]}"; do
            case "$ip" in
                "" | null) cerr "$path — empty ignorePaths entry; nothing to probe"; errored=1; continue ;;
            esac
            rc=0; probeable_path "$ip" || rc=$?  # || keeps set -e off it
            case "$rc" in
                0) ;;
                1) cerr "$path — ignorePaths entry '$ip' is a pattern; the check probes literal paths only"
                   errored=1; continue ;;
                *) cerr "$path — ignorePaths entry '$ip' isn't a clean relative path"
                   errored=1; continue ;;
            esac
            # Local pass — no objects needed. vendir's Walk visits
            # directories and copyFile errors on one, so an entry naming
            # a committed dir — or a gitlink — breaks the next sync.
            # That's a finding, not couldn't-verify: the check DID
            # verify. A committed file is what gets preserved; nothing
            # committed is a note (dead entry — reserved or stale), and
            # the upstream probe still runs: it guards the future shadow.
            # A failed lookup must not read as "nothing committed" — a
            # dead-entry verdict out of thin air.
            lt=$(git -C "$ROOT" ls-tree HEAD -- "$path/$ip" 2>/dev/null) \
                || { cerr "$path — committed-tree lookup failed for '$ip'"; errored=1; continue; }
            lt=${lt%%$'\n'*}; ltype=${lt#* }; ltype=${ltype%% *}
            dead=0
            case "$ltype" in
                tree)   fail "$path — ignorePaths entry '$ip' names a directory in the committed tree — vendir preserves files only; copying it would error the next sync"; found=1; continue ;;
                commit) fail "$path — ignorePaths entry '$ip' names a gitlink (a submodule — an empty dir in the worktree) — vendir preserves files only"; found=1; continue ;;
                blob) ;;
                "")     dead=1
                        note "    dead ignorePaths entry (nothing committed there — reserved or stale); probed anyway:"
                        printf '%s\n' "$path — $ip" | dump_untrusted ;;
            esac
            toprobe+=("$ip"); deads+=("$dead")
        done
        ((${#toprobe[@]})) || continue

        store=""; STORE_RC=0
        make_store "$srcpath" "$srcsha" "$srcurl" || STORE_RC=$?
        store=$STORE_OUT
        if [ "$STORE_RC" != 0 ] || [ -z "$store" ]; then
            cerr "$path — couldn't establish an object store for '$srcpath' at ${srcsha:0:12}… (fetch failed or tree unreadable; entry probes skipped)"
            errored=1; continue
        fi
        for j in "${!toprobe[@]}"; do
            ip=${toprobe[$j]}; dead=${deads[$j]}
            probe="${prefix}$ip"
            # The ls-tree itself is the assertion: a tree entry means the
            # commit contains the path, empty means absent — trees ride
            # every fetch, no blob download needed. A probe error must
            # never read as "absent".
            if out=$(git -C "$store" ls-tree "$srcsha" -- "$probe" 2>/dev/null); then
                if [ -n "$out" ]; then
                    if [ "$dead" = 1 ]; then
                        # Nothing local is preserved today — but the next
                        # sync lands the upstream file under a name
                        # ignorePaths then freezes: a deferred shadow.
                        fail "$path — dead ignorePaths entry '$ip' exists upstream at $srcurl@${srcsha:0:12}… as '$probe' — the next sync lands it, then preservation freezes it in place"
                    else
                        fail "$path — '$ip' exists upstream at $srcurl@${srcsha:0:12}… as '$probe' — the preserved local copy would silently shadow it on the next sync"
                    fi
                    found=1
                else
                    note "    absent upstream at ${srcsha:0:12}…:"
                    printf '%s\n' "$path — $ip" | dump_untrusted
                fi
            else
                cerr "$path — ls-tree probe of '$probe' in '$store' failed — entry not verified"
                errored=1
            fi
        done
    done
    [ -n "$wt" ] && rm -rf "$wt"
    ((found)) && return 1
    ((errored)) && return 2
    return 0
}

check_sync() {
    local paths=() live_paths=() p wt dirty live vver floor
    local vendir_abs b vdir rc renum presraw
    local u dpath durl dsrc ipath f drop ok preserved=()

    # A detached worktree of HEAD: the sync exercises exactly the
    # committed bytes the gate asserts on, and vendir's wipe reaches only
    # the scratch checkout — uncommitted work in the live tree is
    # untouchable.
    wt=$(mktemp -d "${TMPDIR:-/tmp}/vendir-check.XXXXXX") \
        || die "mktemp failed"
    # `worktree remove --force` (the synced tree is dirty, so --force is
    # required) — never `prune --expire now`, which would also reap OTHER
    # worktrees' stale records (a checkout on an unplugged drive dies with
    # it). It deletes only $wt/tree, so the `;` then rm -rf's the mktemp
    # parent — `||` would skip that on success and leak a directory every
    # run. If remove fails, rm -rf still clears the files; the stale admin
    # entry left behind is git's own slow-prune business. The paths are
    # baked into the trap now — `wt` is local and out of scope by the time
    # the EXIT trap fires in the dispatcher's subshell.
    # shellcheck disable=SC2064
    trap "git -C $(printf '%q' "$ROOT") worktree remove --force $(printf '%q' "$wt/tree") 2>/dev/null; rm -rf $(printf '%q' "$wt")" EXIT
    git -C "$ROOT" worktree add --detach --quiet "$wt/tree" HEAD \
        || die "cannot create scratch worktree — is $ROOT a git repository?"

    # Shape check first — a missing or malformed committed config would
    # otherwise fall through to the empty-list message and misreport why.
    cfg 'has("directories") == true' "$wt/tree/vendir.yml" | grep -qx true \
        || die "committed vendir.yml is missing, malformed, or has no 'directories' list"
    # The declared destinations — read from the worktree's vendir.yml
    # (the committed copy vendir read), never the live file: an
    # uncommitted edit would silently shift the coverage assertion
    # below.
    presraw=$(cfg '.directories[].path' "$wt/tree/vendir.yml") \
        || die "directories[] read failed in the scratch worktree's vendir.yml"
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        paths+=("$p")
    done <<< "$presraw"
    ((${#paths[@]})) \
        || die "committed vendir.yml declares no directories — not a vendir repo?"

    [ -f "$wt/tree/Scripts/vendor-sync.sh" ] \
        || die "HEAD has no Scripts/vendor-sync.sh — the recipe the gate replays"
    # Parse before replay — a recipe that doesn't even parse is
    # committed-state broken (a finding), not couldn't-run: a bare
    # shell error produces no stage markers and would misreport as
    # fetch trouble.
    bash -n "$wt/tree/Scripts/vendor-sync.sh" 2>/dev/null \
        || { fail "committed Scripts/vendor-sync.sh fails bash -n — the recipe itself is broken"; return 1; }

    # The replay contacts whatever url: the committed config names, and
    # `directory:` slices read whatever source path it names — a named
    # `vendir-check.sh sync` skips allowlist, so the pinned set is
    # re-asserted over EVERY contents entry (not just contents[0])
    # before the recipe runs. The read must die on failure — an
    # `|| true`-swallowed error would enumerate nothing and re-validate
    # nothing (fail-open on a standalone run).
    renum=$(cfg 'explode(.) | .directories[] | .path as $p | .contents[] | [$p, (.git.url // "-"), (.directory.path // "-")] | @tsv' "$wt/tree/vendir.yml") \
        || die "contents enumeration failed in the scratch worktree's vendir.yml — url/dirsrc re-validation can't run"
    ok=1
    while IFS=$'\t' read -r dpath durl dsrc; do
        [ -n "$dpath" ] || continue
        if [ "$durl" != - ]; then
            for u in $UPSTREAM_URLS; do  # word-split — literals
                [ "$u" = "$durl" ] && break
            done
            [ "$u" = "$durl" ] \
                || { fail "$dpath — git.url '$durl' is outside the declared upstream ($UPSTREAM_URLS)"; ok=0; }
        fi
        if [ "$dsrc" != - ]; then
            for u in $UPSTREAM_DIRSRC; do  # word-split — literals
                [ "$u" = "$dsrc" ] && break
            done
            [ "$u" = "$dsrc" ] \
                || { fail "$dpath — directory.path '$dsrc' repoints the slice source — only $UPSTREAM_DIRSRC holds upstream bytes"; ok=0; }
        fi
        # A contents entry declaring NEITHER type fetches through a
        # source vendir supports but this gate never validated (http:,
        # githubRelease:, inline:) — fail closed on standalone runs.
        [ "$durl" != - ] || [ "$dsrc" != - ] \
            || { fail "$dpath — a contents entry declares neither git: nor directory: (allowlist asserts one)"; ok=0; }
    done <<< "$renum"
    [ "$ok" = 1 ] || return 1

    # The validated vendir is PATH-shimmed into the worktree run: the
    # committed recipe calls bare `vendir`, so the replay must execute
    # exactly the binary this gate checked — a bare-name override like
    # VENDIR=vendir-0.47.0 resolves through `command -v` and shims the
    # same way, or the recipe could silently run a different vendir than
    # the one version-checked below.
    vendir_abs=$(command -v "$VENDIR" 2>/dev/null || true)
    case "$vendir_abs" in
        /*) ;;
        '') die "cannot resolve VENDIR '$VENDIR' to an executable" ;;
        *) vendir_abs=$PWD/${vendir_abs#./} ;;
    esac
    # Two assignments: an assignment's status is its LAST command
    # substitution, so joining the substitutions would mask a failed cd
    # behind basename's success and the `|| die` would never fire.
    vdir=$(cd "$(dirname "$vendir_abs")" && pwd -P) \
        || die "cannot resolve VENDIR path '$vendir_abs'"
    vendir_abs=$vdir/$(basename "$vendir_abs")
    mkdir "$wt/vendir-bin" || die "mkdir failed under $wt"
    ln -s "$vendir_abs" "$wt/vendir-bin/vendir" \
        || die "cannot shim '$vendir_abs' as vendir"
    PATH="$wt/vendir-bin:$PATH"
    vver=$("$VENDIR" version) \
        || die "'$VENDIR version' failed — point VENDIR at a vendir binary"
    printf '%s\n' "$vver" || :
    # Anchor on the 'vendir version ' prefix — a trailing or warning
    # line must not fool the floor compare into an every-run note.
    vver=$(printf '%s\n' "$vver" | sed -n 's/^vendir version //p' | head -1)
    [ -n "$vver" ] || die "'vendir version' printed no 'vendir version <x>' line"
    # A vendir newer than the declared floor can rewrite the lock's
    # format — flag it now so a red sync isn't misread as upstream drift
    # (CI pins exactly the floor).
    floor=$(cfg '.minimumRequiredVersion' "$wt/tree/vendir.yml") \
        || die "minimumRequiredVersion read failed in the scratch worktree's vendir.yml"
    if [ -n "$floor" ] && [ "$floor" != null ] && [ "$vver" != "$floor" ]; then
        note "note: vendir binary version differs from vendir.yml's minimumRequiredVersion:"
        printf '%s\n' "vendir: $vver — floor: $floor" | dump_untrusted
    fi

    # The git-bundle fetch cache: vendir saves the fetched upstream pack
    # as a bundle keyed by sha256(url) and later syncs unbundle + fetch
    # only the delta. Point it at the live repo so this scratch run
    # shares the maintainer's cache — objects are content-addressed, so
    # a stale or partial cache can slow the check but never weaken it.
    export VENDIR_CACHE_DIR="${VENDIR_CACHE_DIR:-$ROOT}"
    export VENDIR_MAX_CACHE_SIZE="${VENDIR_MAX_CACHE_SIZE:-512Mi}"
    # A corrupt bundle fails unbundle loudly (not a fallback) — report
    # the suspect but leave it in place: this is the maintainer's live
    # cache, shared with concurrent vendor-sync runs, and a read-only
    # gate doesn't delete its entries; the named path makes the
    # resulting couldn't-run self-service. list-heads, not verify:
    # verify checks prerequisites against the
    # -C repo, which holds this package's history — a depth-1 bundle's
    # prerequisites live upstream, so verify would flag a healthy bundle
    # corrupt. list-heads only proves the bundle parses, which is the
    # corruption being reported.
    for b in "$VENDIR_CACHE_DIR"/.vendir-cache/fetcher/git-bundle/*/bundle; do
        [ -f "$b" ] || continue
        git bundle list-heads "$b" >/dev/null 2>&1 \
            || note "note: vendir cache entry looks corrupt: $b — left in place; remove it (or '$(dirname "$b")') if the replay dies unbundling it"
    done

    # Coverage assertion: delete the tracked, non-preserved contents of
    # every declared destination before the replay — a recipe that skips
    # a destination (or no-ops outright) then leaves ` D` lines the
    # porcelain read must catch, instead of committed bytes passing for
    # fresh output. ignorePaths entries are excluded: vendir carries
    # preserved files across every sync by design, so they are nobody's
    # coverage contract. (A deliberately hostile recipe can still
    # `git checkout HEAD --` back to clean — that's review's job:
    # vendor-sync.sh sits in the jury's high-risk paths.)
    presraw=$(cfg 'explode(.) | .directories[] | .path as $p | .contents[].ignorePaths[]? | [$p, .] | @tsv' "$wt/tree/vendir.yml") \
        || die "ignorePaths read failed in the scratch worktree's vendir.yml"
    while IFS=$'\t' read -r dpath ipath; do
        [ -n "$dpath" ] || continue
        # vendir treats entries as doublestar patterns — a pattern
        # can't be mirrored by literal-equality preservation: its
        # matched files would be deleted pre-replay, never regenerated,
        # and false-flag ` D`. shadow reports couldn't-verify for the
        # same config, so match that verdict rather than guess.
        rc=0; probeable_path "$ipath" || rc=$?
        [ "$rc" = 0 ] \
            || { cerr "ignorePaths entry '$ipath' is a pattern or unclean path — literal-equality preservation can't mirror it"; return 2; }
        preserved+=("$dpath/$ipath")
    done <<< "$presraw"
    for dpath in "${paths[@]}"; do
        git -C "$wt/tree" ls-files -z -- "$dpath" \
            | while IFS= read -r -d '' f; do
                drop=""
                # ${arr[@]+...} — bash <4.4 errors on "${arr[@]}" of an
                # empty array under set -u (stock macOS bash is 3.2);
                # a vendir.yml with no ignorePaths makes preserved empty.
                for p in ${preserved[@]+"${preserved[@]}"}; do
                    [ "$f" = "$p" ] && { drop=1; break; }
                done
                # A non-final rm -f failure is invisible to the
                # while's exit status (it only reports the last
                # command) — die the subshell so es[1] catches it.
                [ -n "$drop" ] || rm -f -- "$wt/tree/$f" || exit 3
            done
        # A failed ls-files OR a dead while-subshell (the empty-array
        # abort above is one cause) must never silently disarm the
        # assertion — an untouched destination reads clean without the
        # deletions. PIPESTATUS must be captured before any other
        # command runs — the next one overwrites it.
        es=("${PIPESTATUS[@]}")
        [ "${es[0]}" = 0 ] || die "ls-files failed for '$dpath' in the scratch worktree"
        [ "${es[1]}" = 0 ] || die "pre-delete loop aborted for '$dpath' in the scratch worktree"
    done

    # Replay the committed recipe — fetch, patch re-apply, slices,
    # fixups. The recipe's own env defaults pick up VENDIR_CACHE_DIR
    # above; its stage echoes attribute a failure: past `==> git apply`
    # every stage is local and deterministic — a failure there is
    # committed-state drift (a patch that stops applying, a slice or
    # fixup the config moved) — while the fetch stage failing is
    # transport trouble: couldn't-run, never a finding. (The markers are
    # recipe-controlled text — a hostile recipe can print any stage, so
    # the 1-vs-2 attribution is an honest-failure diagnostic, not a
    # trust boundary.)
    if ! (cd "$wt/tree" && bash Scripts/vendor-sync.sh --locked) >"$wt/recipe.log" 2>&1; then
        # The recipe is committed (PR-controlled) code — its output goes
        # through the stop-commands wrapper, not a bare print.
        dump_untrusted < "$wt/recipe.log" 2>/dev/null
        if grep -qE '^(==> git apply|==> vendir sync \(directory slices\)|==> fixups)' "$wt/recipe.log"; then
            fail "vendor-sync.sh --locked failed after the fetch stage (output above) — the committed recipe no longer reproduces"
            return 1
        fi
        die "vendor-sync.sh --locked failed at the upstream-fetch stage (output above)"
    fi

    # The tree must match the committed lock deterministically — read
    # over the WHOLE worktree (no pathspec), not just the declared
    # destinations: a vendir.yml/lock rewrite or recipe output landing
    # outside them can't hide, and --locked still rewrites the lock's
    # `tags:` field — red there with no config change means upstream
    # retagged. --untracked-files=all pins the mode — a developer's
    # status.showUntrackedFiles=no would make --ignored=matching a fatal
    # combination, and the flag overrides that config outright.
    # --ignored=matching makes ignored entries visible as `!!` lines.
    # ONLY .vendir-upstream/'s lines are dropped: it is the one
    # destination that is scratch by design, and everything else that
    # reports `!!` is a finding — the committed .gitignore is
    # PR-controlled too, so an ignore pattern covering a new synced file
    # must surface here rather than be filtered into silence. ` D` lines
    # are the coverage assertion: a file the recipe never regenerated —
    # a skipped destination or a no-op — can never read clean. Captured
    # first so a status failure dies rather than grepping to
    # empty-as-clean.
    dirty=$(git -C "$wt/tree" status --porcelain --untracked-files=all --ignored=matching) \
        || die "git status failed in the scratch worktree"
    dirty=$(printf '%s\n' "$dirty" | grep -v '^!! \.vendir-upstream/' || true)
    if [ -n "$dirty" ]; then
        fail "sync --locked left the committed state changed (D = files the recipe never regenerated):"
        printf '%s\n' "$dirty" | dump_untrusted
        return 1
    fi

    # Advisory only: uncommitted edits in the live tree are not part of
    # this check — the gate asserts committed state — but surface them
    # anyway so a local run still shows the drift it deliberately
    # skipped. Live paths come from the live config; vendir.yml and the
    # lock are in scope so an unsynced edit shows too — and the replay's
    # own inputs (recipe, patches) so a maintainer iterating on them
    # isn't told "ok" while the bytes ignored.
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        live_paths+=("$p")
    done < <(cfg '.directories[].path' || true)
    if ((${#live_paths[@]})); then
        live=$(git -C "$ROOT" status --porcelain --untracked-files=all -- "${live_paths[@]}" vendir.yml vendir.lock.yml Scripts/vendor-sync.sh patches/ || true)
        if [ -n "$live" ]; then
            note "note: uncommitted changes in vendored paths or replay inputs (not checked — sync ran on HEAD):"
            printf '%s\n' "$live" | dump_untrusted
        fi
        [ "${paths[*]}" = "${live_paths[*]}" ] \
            || note "note: vendir.yml's directory list differs from HEAD's — the committed set was checked"
    fi
}

# — dispatch ———————————————————————————————————————————————————————————

usage() {
    cat <<EOF
usage: vendir-check.sh [check ...]

With no arguments, runs every check that exists — the same gate
.github/workflows/vendir-check.yml runs per named step (T011, not yet
landed).
Checks (current): $CHECKS

Env: VENDIR_CHECK_ROOT  repo/fixture under test (default: this repo)
     VENDIR             vendir binary (default: vendir on PATH)
     VENDIR_CACHE_DIR   git-bundle fetch cache dir (sync check: defaults
                        to the live repo root so runs share it)
     VENDIR_MAX_CACHE_SIZE  bundle cache ceiling (default 512Mi)
     VENDIR_CHECK_ALLOW_PROTOCOLS  git transport allowlist (default: https)
     VENDIR_CHECK_UPSTREAM_URLS / VENDIR_CHECK_UPSTREAM_DIRSRC
                        pinned-upstream override (fixtures only — from
                        the invoker's env, never committed config)
     VENDIR_CHECK_DESTINATIONS
                        pinned directories[] set override
     VENDIR_CHECK_DUALLIST_INCLUDE_ENTRY / _EXCLUDE_ENTRY
                        the two entries duallist compares
EOF
}

# Checks that exist, in run order — cheap structural checks first, the
# heavyweight recipe replay last.
CHECKS="allowlist resolve duallist shadow sync"

preflight() {
    local tools=() uniq=() missing=() c t hint bad=0
    for c in "$@"; do
        while IFS= read -r t; do tools+=("$t"); done < <(check_tools "$c")
    done
    ((${#tools[@]})) || return 0
    while IFS= read -r t; do uniq+=("$t"); done < <(printf '%s\n' "${tools[@]}" | sort -u)
    for t in "${uniq[@]}"; do
        if ! command -v "$t" >/dev/null 2>&1; then
            missing+=("$t")
        elif [ "$t" = yq ]; then
            # Identity *and* a v4 floor: apt's python-yq parses explode(.)
            # as a different query language, and a future yq v5 could
            # move explode/@tsv semantics — either would silently mislead
            # a config read rather than fail.
            case "$(yq --version 2>&1)" in
                *"version v4."*) ;;
                *mikefarah*) fail "yq is mikefarah/yq but not v4.x — CI's image ships v4"; bad=1 ;;
                *) fail "yq on PATH is not mikefarah/yq — install: brew install yq"; bad=1 ;;
            esac
        fi
    done
    if ((${#missing[@]})); then
        while IFS= read -r t; do
            hint=$(tool_hint "$t")
            fail "required tool missing: $t${hint:+ — install: $hint}"
        done < <(printf '%s\n' "${missing[@]}" | sort -u)
        bad=1
    fi
    # url.<base>.insteadOf rewrites (a common ~/.gitconfig maps
    # https://github.com/ to ssh, or to a mirror host) redirect every
    # probe and vendir fetch. Audit the layer the calls actually see:
    # vendir fetches from its own temp repo and ls-remote runs with
    # -C /, so both see only system+global(+env) — never $ROOT's or the
    # caller's repo-local rules. Flag any rule whose matched prefix hits
    # a committed url: and yields a DIFFERENT effective url — an
    # https→https host or path swap stays inside GIT_ALLOW_PROTOCOL yet
    # still moves the pinned upstream's provenance, while an identity
    # rewrite (eff == url) is harmless canonicalization. --get-regexp -z:
    # one NUL record per rule, key\nvalue — the replacement base lives
    # in the KEY (url.<base>.insteadof). Run it only when a requested
    # check fetches over git — resolve, shadow, and sync all can — so an
    # unrelated rewrite can't gate the offline checks. Escape hatch for
    # a deliberate mirror: run with GIT_CONFIG_GLOBAL=/dev/null.
    local fetch=0
    for c in "$@"; do
        case "$c" in resolve | shadow | sync) fetch=1 ;; esac
    done
    ((fetch)) || return "$bad"
    local committed_urls rule repkey rep orig eff u
    committed_urls=$(git -C "$ROOT" show HEAD:vendir.yml 2>/dev/null \
        | yq 'explode(.) | .directories[].contents[].git | select(. != null) | .url' - 2>/dev/null) \
        || die "committed vendir.yml url enumeration failed — the insteadOf audit can't run"
    while IFS= read -r -d '' rule; do
        repkey=${rule%%$'\n'*}; rep=${repkey#url.}; rep=${rep%.insteadof}
        orig=${rule#*$'\n'}
        [ -n "$orig" ] || continue  # an empty insteadOf value matches nothing
        while IFS= read -r u; do
            [ -n "$u" ] || continue
            [ "${u:0:${#orig}}" = "$orig" ] || continue
            eff=$rep${u:${#orig}}
            [ "$eff" = "$u" ] && continue
            fail "git config '$repkey' rewrites committed url '$u' to '$eff' — a non-identity insteadOf moves the pinned upstream's provenance; remove the rule or run with GIT_CONFIG_GLOBAL=/dev/null"
            bad=1; break
        done <<< "$committed_urls"
    done < <(git -C / config --get-regexp -z '^url\..*\.insteadof$' 2>/dev/null || true)
    return "$bad"
}

main() {
    case "${1:-}" in -h | --help) usage; exit 0 ;; esac

    local c rc sig failed="" errored="" known ok allow_failed=""
    # shellcheck disable=SC2086 # $CHECKS is a literal word list — splitting is the point.
    if [ $# -eq 0 ]; then set -- $CHECKS; fi
    for c; do
        ok=0
        for known in $CHECKS; do
            [ "$c" = "$known" ] && { ok=1; break; }
        done
        [ "$ok" = 1 ] || die "unknown check '$c' (available: $CHECKS)"
    done
    preflight "$@" || exit 2
    # Foreground checks + record-the-signal traps. A terminal Ctrl-C hits
    # the whole process group — the check subshell dies on its own default
    # disposition and bash runs its EXIT trap, so the scratch worktree is
    # still cleaned — while the parent's traps only record the code so the
    # run exits with it once the check returns. The residual delay: a
    # signal sent to the parent PID alone (kill, or a CI cancel's SIGINT)
    # waits until the current check returns — bounded; CI escalates to
    # SIGKILL anyway. Do NOT background the checks under job control: a
    # background pgrp that touches the terminal (a stdin read, or
    # `stty tostop`) stops dead and `wait` hangs forever.
    sig=""
    trap 'sig=129' HUP
    trap 'sig=130' INT
    trap 'sig=143' TERM
    for c; do
        [ -z "$sig" ] || exit "$sig"
        # An allowlist failure stops the network legs in this run —
        # otherwise resolve/shadow/sync would go on to contact the very
        # host the gate just flagged. Each fetching check re-validates
        # its urls too, so this is belt on suspenders, not the only
        # line; a named `vendir-check.sh resolve` without allowlist in
        # the set still runs (and still re-validates).
        if [ -n "$allow_failed" ]; then
            case "$c" in
                resolve | shadow | sync)
                    note "==> $c"
                    note "    $c: skipped — allowlist flagged the committed upstream"
                    continue ;;
            esac
        fi
        note "==> $c"
        rc=0
        ( "check_$c" ) || rc=$?
        [ -z "$sig" ] || { note "    $c: interrupted" 2>/dev/null || true; exit "$sig"; }
        case "$rc" in
            0) note "    $c: ok" ;;
            1) failed="${failed:+$failed }$c"; note "    $c: FAILED"; [ "$c" = allowlist ] && allow_failed=1 ;;
            2) errored="${errored:+$errored }$c"; note "    $c: ERRORED" ;;
            *) if [ "$rc" -ge 128 ]; then
                   note "    $c: killed (signal $((rc - 128))) — aborting run"
                   exit "$rc"
               fi
               errored="${errored:+$errored }$c"
               note "    $c: ERRORED (exited $rc — outside the 0/1/2 check contract)" ;;
        esac
    done
    # Findings dominate trouble: a check that proved drift says something
    # certain about the tree — a check that merely couldn't run does not.
    # Print both lists; exit 2 only when nothing produced a finding.
    if [ -n "$failed" ] || [ -n "$errored" ]; then
        local msg=${failed:+failed check(s): $failed}
        [ -z "$errored" ] || msg="${msg:+$msg; }could not run: $errored"
        echo "error: $msg" >&2
        [ -z "$failed" ] || exit 1
        exit 2
    fi
    exit 0
}

main "$@"
