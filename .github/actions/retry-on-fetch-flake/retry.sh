#!/usr/bin/env bash
# retry.sh — the loop behind the retry-on-fetch-flake composite action.
#
# Re-runs a command up to RETRY_MAX_ATTEMPTS times ONLY when the attempt's
# output matches a retryable fetch/transport signature from signatures.tsv
# (kind/pattern/sample columns — the file is the single source of truth for
# both this gate and the selftest harness; add a signature there and the
# selftest picks it up automatically). Auth-shaped output (the file's
# `noretry` rows) is checked BEFORE the retryable set and exits immediately
# with the real code — a dead credential must never burn three attempts.
# Anything matching neither set also exits with the real code: retries never
# mask a failure they can't classify.
#
# Wrap fetch-only commands (`swift package resolve`, `tuist generate`,
# `xcodebuild -resolvePackageDependencies`) — re-running is only safe when
# the work is idempotent. Never wrap build/test steps.
#
# Invocation: called by action.yml, or directly in the selftest. Inputs
# arrive as env vars (the action maps inputs→env; nothing is positional):
#   RETRY_COMMAND          command text, run via `bash -eo pipefail -c`
#   RETRY_LABEL            short name for group/error lines (default: "command")
#   RETRY_MAX_ATTEMPTS     total attempts (default: 3)
#   RETRY_BACKOFF_SECONDS  linear backoff unit — waits BACKOFF*attempt
#                          between attempts (default: 20)
#   RETRY_CLEANUP_DIRS     directories wiped between attempts, one per line,
#                          taken literally (no ~/$VAR/glob expansion; relative
#                          paths resolve against the workspace root —
#                          $GITHUB_WORKSPACE on a runner, the caller's cwd
#                          off-runner) — each must normalize strictly inside
#                          that root or $RUNNER_TEMP or it is warned on and
#                          skipped (default: ".build"; an explicitly EMPTY
#                          value disables the wipe entirely)
#   RETRY_SIGNATURES       signature table path (default: signatures.tsv
#                          beside this script)
#
# Verdicts print as the LAST stdout lines (attempts=<n>, exit_code=<rc>,
# verdict=<word>) and append to $GITHUB_OUTPUT when set — the machine channel
# both the action's outputs mapping and a direct invocation in the selftest
# can read. verdict is one of: success | retry-exhausted | auth-shaped |
# unclassified | table-missing | usage — one word per way the run can end, so
# a test distinguishes the auth exclusion from an unclassifiable failure
# without grepping English prose.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CMD=${RETRY_COMMAND:-}
LABEL=${RETRY_LABEL:-command}
MAX=${RETRY_MAX_ATTEMPTS:-3}
BACKOFF=${RETRY_BACKOFF_SECONDS:-20}
# `-` not `:-`: an explicitly EMPTY value is the caller asking for no wipe —
# only an unset var earns the .build default (the toolkit#272 distinction).
CLEANUP_DIRS=${RETRY_CLEANUP_DIRS-.build}
SIG_FILE=${RETRY_SIGNATURES:-"$SCRIPT_DIR/signatures.tsv"}
LOG="${RUNNER_TEMP:-/tmp}/retry-on-fetch-flake.$$.log"
# A runner wipes RUNNER_TEMP per job; locally /tmp would accumulate one log
# per run — the tee'd stream already carried the same bytes to stderr.
trap 'rm -f -- "$LOG"' EXIT

# Publish the verdict before EVERY terminal exit — the composite's outputs:
# mapping and the selftest both read these; $GITHUB_OUTPUT may be unset in a
# direct local invocation.
finish() {
  echo "attempts=$1"
  echo "exit_code=$2"
  echo "verdict=$3"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      echo "attempts=$1"
      echo "exit_code=$2"
      echo "verdict=$3"
    } >> "$GITHUB_OUTPUT"
  fi
  exit "$2"
}

fail_usage() {
  echo "::error::retry-on-fetch-flake: $1"
  finish 0 2 usage
}
[ -n "$CMD" ] || fail_usage "RETRY_COMMAND is empty"
[ "$MAX" -ge 1 ] 2>/dev/null || fail_usage "RETRY_MAX_ATTEMPTS='$MAX' is not a positive integer"
[ "$BACKOFF" -ge 0 ] 2>/dev/null || fail_usage "RETRY_BACKOFF_SECONDS='$BACKOFF' is not a non-negative integer"

# The one canonical root for relative cleanup-dirs entries — resolved here so
# resolve_guarded and wipe_dirs can't disagree. The test is emptiness, not
# just unset (`:-` catches both — the SC2115 gap): off-runner the caller's cwd
# is the root a shell user already means by `cleanup-dirs: .build`, and a
# notice says so when a wipe actually happens; on a runner a missing
# workspace means a broken environment — refuse rather than guess.
WORKSPACE_ROOT=${GITHUB_WORKSPACE:-}
if [ -z "$WORKSPACE_ROOT" ]; then
  [ "${GITHUB_ACTIONS:-}" = "true" ] &&
    fail_usage "GITHUB_WORKSPACE is empty on a runner — a broken environment"
  WORKSPACE_ROOT=$PWD
  WORKSPACE_LOCAL=1
else
  WORKSPACE_LOCAL=0
fi

# --- Signature table ------------------------------------------------------
# Read kind<TAB>pattern pairs from signatures.tsv; `#' comments and blank
# lines skipped. The file ships beside the script — a missing file is a
# packaging bug: run the command once, unretried, and say so loudly rather
# than silently disabling the retry the caller wired.
RETRY_PATTERNS=()
NORETRY_PATTERNS=()
TABLE_OK=0
if [ -f "$SIG_FILE" ]; then
  TABLE_OK=1
  while IFS=$'\t' read -r kind pattern rest || [ -n "$kind" ]; do
    case "$kind" in ''|\#*) continue ;; esac
    case "$kind" in
      retry)   RETRY_PATTERNS+=("$pattern") ;;
      noretry) NORETRY_PATTERNS+=("$pattern") ;;
    esac
  done < "$SIG_FILE"
fi

# $1 = log, $2 = error direction: "match" fails closed for the noretry set —
# a broken auth pattern must not let retries resume — and "miss" for the
# retry set, so a broken retry row can't become retry-on-anything. grep rc:
# 0=match, 1=no match, ≥2=broken pattern or unreadable log. rc≥2 emits a loud
# error line plus the fail-closed direction: a regex THIS grep build rejects
# is invisible to CI's self-match, which runs a different one (BSD vs GNU ERE
# differ on escapes like \s and \b).
matches_any() {
  local log=$1 on_err=$2 pat rc; shift 2
  for pat in "$@"; do
    [ -z "$pat" ] && continue
    grep -qE -- "$pat" "$log" 2>/dev/null; rc=$?
    [ "$rc" -eq 0 ] && return 0
    if [ "$rc" -ge 2 ]; then
      echo "::error::signature /$pat/ errored (grep rc=$rc) — treating as a $on_err"
      [ "$on_err" = match ] && return 0
    fi
  done
  return 1
}

# --- cleanup-dirs guard ---------------------------------------------------
# Resolve one entry to an absolute path, or fail. Entries are literal —
# `~`, `$HOME`, `$VAR`, `*` are never expanded (a literal `*` is a path
# named `*`). Existing path prefixes resolve through symlinks; for a missing
# tail the deepest EXISTING ancestor resolves and the remainder is lexical —
# `link/newdir` with `link` a symlink to /etc resolves out, which a text-only
# check would miss. macOS realpath has no -m, so the walk is hand-written.
resolve_guarded() {
  local entry=$1 resolved='' cand rp part
  [ -n "$entry" ] || return 1
  case "$entry" in /*) ;; *) entry="$WORKSPACE_ROOT/$entry" ;; esac
  local IFS='/'
  set -f
  # Splitting on '/' IS the point — components can't contain '/'. set -f
  # keeps a literal '*' component from globbing into the workspace.
  # shellcheck disable=SC2206
  local -a parts=($entry)
  set +f
  unset IFS
  for part in "${parts[@]}"; do
    case "$part" in
      ''|'.') continue ;;
      '..') resolved=${resolved%/*} ;;  # pop; empty → stays at root
      *)
        cand="$resolved/$part"
        if [ -e "$cand" ] || [ -L "$cand" ]; then
          # A BROKEN SYMLINK can't be canonicalized (macOS realpath fails on
          # its missing target) — keep the lexical path: the link node at
          # this address is what rm removes, and the address is already
          # inside the root. Other realpath failures still fail closed.
          if ! rp=$(realpath "$cand" 2>/dev/null); then
            [ -L "$cand" ] && { resolved=$cand; continue; }
            return 1
          fi
          resolved=$rp
        else
          resolved=$cand
        fi ;;
    esac
  done
  printf '%s' "$resolved"
}

wipe_dirs() {
  local ws tmp resolved entry wiped=0
  [ "$WORKSPACE_LOCAL" = 1 ] &&
    echo "::notice::not on a runner — cleanup-dirs rooted at $WORKSPACE_ROOT"
  ws=$(realpath "$WORKSPACE_ROOT" 2>/dev/null) || ws=$WORKSPACE_ROOT
  tmp=$(realpath "${RUNNER_TEMP:-/tmp}" 2>/dev/null) || tmp=${RUNNER_TEMP:-/tmp}
  while IFS= read -r entry || [ -n "$entry" ]; do
    [ -z "$entry" ] && continue
    resolved=$(resolve_guarded "$entry") || resolved=''
    # Strictly inside one canonicalized root — the roots themselves refuse.
    case "$resolved" in
      "$ws"/?* | "$tmp"/?*) ;;
      *) echo "::warning::cleanup-dirs entry '$entry' resolves outside the job's trees — skipped"; continue ;;
    esac
    if [ -e "$resolved" ] || [ -L "$resolved" ]; then
      rm -rf -- "$resolved"
      wiped=$((wiped + 1))
    else
      echo "::warning::cleanup-dirs entry '$entry' ($resolved) names nothing — a misspelled path disables half the wipe"
    fi
  done <<< "$CLEANUP_DIRS"
  [ "$wiped" -gt 0 ] && echo "wiped $wiped resolution dir(s) before retry"
  return 0
}

# --- The loop -------------------------------------------------------------
attempt=1
while true; do
  echo "::group::$LABEL — attempt $attempt/$MAX"
  [ "$TABLE_OK" -eq 0 ] && [ "$attempt" -eq 1 ] &&
    echo "::error::signature table '$SIG_FILE' missing — running once, unretried"
  # `bash -c` does not inherit the composite's `shell: bash` -e flag, so -e
  # is explicit: a multi-line command still dies on its first failed line.
  # PIPESTATUS is read as the very next statement — inside `if ! cmd | tee`,
  # $? is the `!`'s result (always 0) and a real failure would go green.
  bash -eo pipefail -c "$CMD" 2>&1 | tee "$LOG"
  rc=${PIPESTATUS[0]}
  echo "::endgroup::"

  if [ "$rc" -eq 0 ]; then
    if [ "$attempt" -gt 1 ]; then
      echo "::warning::$LABEL passed on attempt $attempt — a retry burned a fetch flake"
      [ -n "${GITHUB_STEP_SUMMARY:-}" ] &&
        echo "- \`$LABEL\`: passed on attempt $attempt/$MAX after a fetch-signature failure" >> "$GITHUB_STEP_SUMMARY"
    fi
    finish "$attempt" 0 success
  fi

  # Exclusion first: auth-shaped output wins even when a transport signature
  # also matches (e.g. `RPC failed; HTTP 403`) — a dead credential must never
  # burn three attempts. The `${arr[@]+...}` idiom keeps an empty pattern set
  # from tripping `set -u` on bash 3.2's empty-array expansion bug.
  if [ "$TABLE_OK" -eq 1 ] &&
    matches_any "$LOG" match "${NORETRY_PATTERNS[@]+"${NORETRY_PATTERNS[@]}"}"; then
    echo "::error::$LABEL failed with an auth-shaped error — not retrying (rc=$rc)"
    finish "$attempt" "$rc" auth-shaped
  fi
  if [ "$TABLE_OK" -eq 0 ]; then
    echo "::error::$LABEL failed and no signature table is loaded — cannot classify (rc=$rc)"
    finish "$attempt" "$rc" table-missing
  fi
  if ! matches_any "$LOG" miss "${RETRY_PATTERNS[@]+"${RETRY_PATTERNS[@]}"}"; then
    echo "::error::$LABEL failed — not a dependency-fetch flake; not retrying (rc=$rc)"
    finish "$attempt" "$rc" unclassified
  fi
  if [ "$attempt" -ge "$MAX" ]; then
    echo "::error::$LABEL hit the dependency-fetch flake $MAX times (rc=$rc)"
    finish "$attempt" "$rc" retry-exhausted
  fi

  echo "dependency-fetch flake — retrying $LABEL (attempt $((attempt + 1))/$MAX in $((BACKOFF * attempt))s)"
  wipe_dirs
  sleep $((BACKOFF * attempt))
  attempt=$((attempt + 1))
done
