#!/usr/bin/env bash
# verify-scope.sh — FR-008 canary: does the ambient github.com credential carry
# push access? Probes the receive-pack ref-discovery call every `git push` makes
# first, not the repo object's `permissions` field — that field reports a *user's*
# permissions and is structurally all-false for an app installation token (what a
# job's GITHUB_TOKEN is), so it can never report write (semantic-release/github#182).
# `push --dry-run` performs the discovery and nothing else — read-only on the wire,
# and it authenticates through the URL-scoped global extraheader this action wrote,
# i.e. the exact channel a persisted write token would abuse.
#
# Verdicts: can-push | read-only | inconclusive — printed as the LAST stdout line
# (`scope=<v>`) and appended to $GITHUB_OUTPUT when set, so both the action's
# outputs mapping and a direct invocation in the selftest can read it.

set -u

# The refspec needs a valid dst name (components can't start with '.'), but it
# is only a vehicle — ref discovery, where the auth check happens, runs first.
# GITHUB_REPOSITORY is guarded rather than assumed: this script must never
# fail — an unbound var under set -u would exit 1 and fail the calling step,
# breaking the warn-only contract.
REPO="${GITHUB_REPOSITORY:-}"
if [ -z "$REPO" ]; then
  OUT="GITHUB_REPOSITORY unset — cannot build probe URL"
  RC=99
else
  OUT=$(GIT_TERMINAL_PROMPT=0 git -C "${GITHUB_WORKSPACE:-.}" push --dry-run \
    "https://github.com/${REPO}" "HEAD:refs/heads/selftest-scope-probe" 2>&1)
  RC=$?
fi

# read-only must mean "credentials were offered and push was refused" —
# GitHub answers 403/permission-denied on receive-pack discovery for a
# valid but insufficient token. Deliberately absent from the pattern:
# "could not read Username" and "authentication failed" are the 401
# channel — the server never judged push permission (credential absent
# or unacceptable), so they fall through to inconclusive rather than
# masquerading as a proved read-scope.
if [ "$RC" -eq 0 ]; then
  VERDICT=can-push
elif printf '%s' "$OUT" | grep -qiE '403|denied|not authorized'; then
  VERDICT=read-only
else
  VERDICT=inconclusive
fi

case "$VERDICT" in
  can-push)
    echo "::warning::job's GITHUB_TOKEN can push to the repository — this action is meant for contents: read jobs" ;;
  read-only)
    echo "job token is read-scoped (push-discovery probe refused)" ;;
  inconclusive)
    echo "::notice::token scope check inconclusive — push probe failed without a push-permission refusal (rc=$RC)"
    # OUT is safe to show: git errors echo URLs, never credential values, and
    # both token forms are masked regardless — the evidence lands in the log
    # instead of requiring a re-run to see what git said.
    echo "::group::push --dry-run output"; printf '%s\n' "$OUT"; echo "::endgroup::" ;;
esac

echo "scope=$VERDICT"
[ -n "${GITHUB_OUTPUT:-}" ] && echo "scope=$VERDICT" >> "$GITHUB_OUTPUT"
exit 0
