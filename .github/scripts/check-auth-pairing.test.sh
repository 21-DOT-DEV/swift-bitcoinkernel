#!/usr/bin/env bash
# check-auth-pairing.test.sh — runs check-auth-pairing.sh over each fixture
# case under testdata/auth-pairing/ and asserts its verdict.
#
#   ok-*   directories must lint clean (exit 0);
#   fail-* directories must exit non-zero with at least one violation whose
#          text matches the case's expected substring in WANT below —
#          asserting the *reason*, not just that something failed.
#
# An unrecognized fail-* name (no WANT entry) fails the case, so every
# failure fixture stays documented here. Output is TAP-shaped: one
# `ok`/`not ok` line per case plus a `1..N` plan line.

set -u
cd "$(dirname "$0")" || exit 2

CASES=testdata/auth-pairing

# Expected violation substring per fail-* case; "" means "no mapping yet" —
# the assert below fails such a case so every fixture stays documented here.
want_for() {
	case "$1" in
	fail-checkout-order) echo "ordered after github-git-auth" ;;
	fail-checkout-persist) echo "lacks persist-credentials: false" ;;
	fail-checkout-true) echo "lacks persist-credentials: false" ;;
	fail-empty-marker) echo "write-capable effective permission scope(s): contents" ;;
	fail-exempt-checkout-still-applies) echo "lacks persist-credentials: false" ;;
	fail-marker-outside) echo "outside actions-selftest.yml" ;;
	fail-missing-permissions) echo "inherits the repository default" ;;
	fail-missing-token) echo "missing the required token input" ;;
	fail-workflow-write) echo "write-capable effective permission scope(s): contents" ;;
	fail-write-all) echo "write-all" ;;
	fail-write-scope) echo "write-capable effective permission scope(s): contents" ;;
	*) echo "" ;;
	esac
}

n=0
failed=0
for casedir in "$CASES"/*/; do
	name=$(basename "$casedir")
	n=$((n + 1))
	if out=$(bash ./check-auth-pairing.sh "$casedir" 2>&1); then
		rc=0
	else
		rc=$?
	fi
	if [[ $name == ok-* ]]; then
		if [[ $rc -eq 0 ]]; then
			printf 'ok %d - %s\n' "$n" "$name"
		else
			printf 'not ok %d - %s (expected clean lint; exit %d)\n' "$n" "$name" "$rc"
			printf '%s\n' "$out" | sed 's/^/  /'
			failed=$((failed + 1))
		fi
	else
		want=$(want_for "$name")
		if [[ $rc -ne 0 && -n $want && $out == *"$want"* ]]; then
			printf 'ok %d - %s\n' "$n" "$name"
		else
			printf 'not ok %d - %s (expected a failure matching %q; exit %d)\n' "$n" "$name" "$want" "$rc"
			printf '%s\n' "$out" | sed 's/^/  /'
			failed=$((failed + 1))
		fi
	fi
done

printf '1..%d\n' "$n"
if ((failed > 0)); then
	printf '%d fixture case(s) failed\n' "$failed" >&2
	exit 1
fi
echo "all fixture cases behaved as expected"
