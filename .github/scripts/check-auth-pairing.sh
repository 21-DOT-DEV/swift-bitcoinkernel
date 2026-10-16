#!/usr/bin/env bash
# check-auth-pairing.sh — mechanically enforces the github-git-auth pairing
# rules (FR-009) across a directory of workflow files.
#
# For every job whose steps `uses:` the github-git-auth action (in either the
# `./` or `$/` local-reference form), this fails the run when:
#
#   1. the job's effective GITHUB_TOKEN permissions are write-capable — the
#      job's `permissions:` block if present, otherwise the workflow's; any
#      `write` value or `write-all` counts, and NO block at either level fails
#      too, since the token then inherits the repository default (which may
#      be write). A job-level `env:` entry `AUTH_LINT_EXEMPT: "<reason>"`
#      lifts ONLY this rule — and only inside actions-selftest.yml.
#   2. an actions/checkout step lacks `persist-credentials: false` —
#      checkout's persisted credential plus the action's global extraheader
#      sends two Authorization headers, which github.com answers with a bare
#      400;
#   3. a checkout step is ordered AFTER the auth step — the checkout's own
#      fetch double-headers the same way and fails outright, so pairing
#      means auth *after* every checkout, not merely both present;
#   4. the github-git-auth step is missing its required `token` input —
#      actionlint ≤1.7.12 can't parse `uses: $/…` (rhysd/actionlint#732), so
#      its input check never sees those steps.
#
# Separately, any file containing the text AUTH_LINT_EXEMPT fails unless it is
# named actions-selftest.yml — the marker exists only for that workflow's
# deliberate write-scoped FR-008 canary.
#
# Jobs without `steps:` (reusable-workflow calls) are skipped — the lint only
# sees what this repository's files declare, and docker-builds' unpersisted
# checkout plus docc-release's write-scoped `release` job stay exempt because
# neither uses the action.
#
# Usage: check-auth-pairing.sh [workflow-dir]   (default: .github/workflows)
# Prints one GitHub `::error` annotation per violation; exits 1 if any found.

set -euo pipefail

DIR="${1:-.github/workflows}"

for tool in yq jq; do
	if ! command -v "$tool" >/dev/null; then
		printf '::error::%s not found on PATH (both are preinstalled on GitHub ubuntu-latest)\n' "$tool" >&2
		exit 2
	fi
done

violations=0
report() {
	printf '::error file=%s::%s\n' "$1" "$2"
	violations=$((violations + 1))
}

shopt -s nullglob
files=("$DIR"/*.yml "$DIR"/*.yaml)
if ((${#files[@]} == 0)); then
	printf '::error::no workflow files found under %s\n' "$DIR" >&2
	exit 2
fi

# The jq program emits one line per violation; bash wraps them as annotations.
read -r -d '' JQ_PROGRAM <<'JQ' || true
	def is_auth:
		(.uses // "" | tostring) | test("\\.github/actions/github-git-auth");
	def is_checkout:
		(.uses // "" | tostring) | test("^actions/checkout");
	def perm_msg($p):
		if $p == null then
			"no permissions declared at job or workflow level — the token inherits the repository default, which may be write"
		elif ($p | type) == "string" then
			if $p == "write-all" then "effective permissions: write-all" else empty end
		elif ($p | type) == "object" then
			([$p | to_entries[] | select(.value == "write") | .key] | join(", ")) as $w
			| if ($w | length) > 0 then "write-capable effective permission scope(s): \($w)" else empty end
		else "unreadable permissions shape" end;

	. as $top
	| ($top.jobs // {} | to_entries[]) as $j
	| ($j.value.steps // []) as $steps
	| [range(0; $steps | length) | select($steps[.] | is_auth)] as $auth
	| select($auth | length > 0)
	| ($auth | min) as $first_auth
	| [range(0; $steps | length) | select($steps[.] | is_checkout)] as $ck
	| (($j.value.env.AUTH_LINT_EXEMPT // "") | tostring) as $marker
	| (
		(if ($exempt and ($marker | length) > 0) then empty
		 else (perm_msg($j.value.permissions // $top.permissions)
		       | "job \($j.key | @json) uses github-git-auth with \(.)")
		 end),
		($ck[] | . as $i
			| select(($steps[$i].with["persist-credentials"]) as $v
			         | ($v != false and $v != "false"))
			| "job \($j.key | @json): actions/checkout step #\($i + 1) lacks persist-credentials: false — checkout's credential plus the global extraheader sends two Authorization headers"),
		($ck[] | . as $i | select($i > $first_auth)
			| "job \($j.key | @json): actions/checkout step #\($i + 1) is ordered after github-git-auth — the checkout's own fetch double-headers and fails with a bare 400"),
		($auth[] | . as $i
			| select((($steps[$i].with.token // "") | tostring | length) == 0)
			| "job \($j.key | @json): github-git-auth step #\($i + 1) is missing the required token input")
	)
JQ

for f in "${files[@]}"; do
	base=$(basename "$f")

	if grep -q 'AUTH_LINT_EXEMPT' "$f" && [ "$base" != "actions-selftest.yml" ]; then
		report "$f" "AUTH_LINT_EXEMPT marker outside actions-selftest.yml — the exemption exists only for that workflow's deliberate FR-008 canary"
	fi

	if ! json=$(yq -o=json '.' "$f" 2>/dev/null); then
		report "$f" "unparseable YAML — yq could not read this workflow"
		continue
	fi

	[ "$base" = "actions-selftest.yml" ] && exempt=true || exempt=false

	while IFS= read -r line; do
		[ -n "$line" ] && report "$f" "$line"
	done < <(jq -r --argjson exempt "$exempt" "$JQ_PROGRAM" <<<"$json")
done

if ((violations > 0)); then
	printf '%d auth-pairing violation(s)\n' "$violations" >&2
	exit 1
fi
echo "auth-pairing: every github-git-auth job satisfies the pairing rules"
