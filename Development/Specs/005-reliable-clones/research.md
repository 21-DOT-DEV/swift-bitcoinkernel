# Research — 005 · Authenticate github.com clones and retry fetch flakes in CI

Evidence and rejected alternatives for [the plan](./plan.md). Spec in
[spec.md](./spec.md); ordered work in [tasks.md](./tasks.md).

## 1. Root cause — anonymous-clone throttling

**Diagnosis: every fetch in the failing job was anonymous, and GitHub
throttles anonymous clones on a shared per-IP quota.** Evidence: run
38030982512 attempt 1 (`KernelApp (ios)`, `tuist generate` step) shows
`swift-event` dying on `Recv failure: Operation timed out` at an anonymous
clone, then SwiftPM fataling on `git -C …/swift-event-5458ed10` → `No such
file or directory` — while `swift-plugin-tuist` took 569 s to fetch, the
throttle signature (with one ambiguity: that line may be the plugin's
release-asset binary download rather than the git clone — an HTTPS channel
the header can't authenticate; either way the anonymous `swift-event`
`Recv failure` clone stands as the clone-path evidence). Upstream
confirmation: cli/cli#14329 documents that
anonymous clones of *public* repos hit "GitHub is temporarily limiting some
unauthenticated downloads… please authenticate" — GitHub's own message names
the fix. Context: StatusGator logged a ~2-day GitHub Actions incident ending
Oct 7, three days before this run — platform instability was elevated, which
argues for the retry layer staying even with auth in place.

## 2. Auth mechanism — preemptive `extraheader`, not URL credentials

**Chosen: `git config --global http.https://github.com/.extraheader
"AUTHORIZATION: basic <b64(x-access-token:TOKEN)>"`.** This is the same
mechanism `actions/checkout` uses for the workspace checkout (visible as
`extraheader = AUTHORIZATION: basic ***` in checkout's persisted
credential file) and the one
cli/cli#14329 recommends for `gh`. Rejected: `url.https://TOKEN@github.com/
.insteadOf` — git only sends URL credentials after a 401 challenge, and
github.com answers 200 for public repos without challenging, so the token is
never sent; credential helpers — consulted only after a 401, same trap;
`.netrc` — a second secret file to manage, solving the same problem worse;
SSH deploy keys — different trust model, adds key management for a
read-scope need. The header goes out on the FIRST request, which is what
authenticates the clone.

## 3. Delivery — the global config FILE, not environment injection

**Chosen: write `~/.gitconfig`.** xcodebuild's default `-scmProvider xcode`
fetches packages in-process and reads the config file directly; a
`GIT_CONFIG_GLOBAL` env redirect is ignored there — verified on RELIABLE-CLONE
— which would silently leave every xcodebuild resolution anonymous while
SwiftPM's shell-outs kept working. `GIT_CONFIG_COUNT` inline config does reach
git-subprocess fetchers but not the file-reading path. The file covers every
fetcher uniformly. Cost accepted: the token sits in `~/.gitconfig` for the
job's life (composite actions cannot register post steps) — acceptable on
ephemeral hosted runners with a `contents: read` token on a public repo,
enforced by keeping write-scoped jobs out of the wiring (§9); explicitly
documented do-not-use on self-hosted runners. One reach caveat: whether
xcodebuild's in-process package fetcher honors `http.lowSpeed*` is
unverified — a libgit2-based fetcher would read the config file but honor
only a subset of http settings; if it ignores them, a stalled xcodebuild
fetch crawls until its job bound — and `apple-builds`' xcodebuild steps
have none (`tuist-apps` rises to 75 and `flake-hunt` carries 120, so the
deferred job-caps item is apple-builds' only backstop).

## 4. Pairing — `persist-credentials: false` wherever auth runs

**Chosen: required, not optional.** checkout's default persists a repo-local
github.com credential — as of v6, in a *separate file* included by the
repo's config (checkout#2286), not written into `.git/config` directly —
which combined with the global extraheader sends TWO `Authorization`
headers and github.com answers a bare `400 Duplicate header` — reproduced
locally on RELIABLE-CLONE. With persistence off, the global header is the
only one and covers in-repo commands too. The separate-file detail also
decides where the count check must look: inside the workspace with
`--includes`, because a `--global`-only count is blind to it (§7). Ordering matters equally: a
checkout placed *after* the auth step sends its own credential plus the
global header on the fetch itself → the 400 hits checkout, not a warning —
so the pairing rule is auth-*after*-checkouts, not merely both-present.
Honest
side note: OWASP recommends `persist-credentials: false` as baseline —
cited here as incidental alignment, not a security gain; the global config
re-persists the same read-scoped token, so token-on-disk exposure is
unchanged by this choice.

## 5. Cache path — `--disable-dependency-cache`

**Chosen: fetch straight into `.build/repositories` — on every
`swift`-family step that resolves, not just the two `tuist generate`
calls.** The incident's fatal line — `git -C …/swift-event-5458ed10 …: No
such file or directory` — is swiftlang/swift-package-manager#9037: a clone
dying mid-fetch into the shared cache leaves a path SwiftPM later `git
-C`s into and cannot re-enter. `swift test`, `swift run`, and
`generate-documentation` resolve through the same shared cache — leaving
the flag off them would close the crash path in 2 of ~8 fetch points while
claiming the whole thing. The flag costs nothing on a fresh runner (the
cache starts empty) and is accepted by `swift test`/`build`/`run` (verified
on the current toolchain; plugin subcommands take it as a `swift package`
option). The Dockerfile `RUN` lines are `swift`-family steps too — the flag
is a plain CLI arg, so it reaches in-container where the git config cannot.
xcodebuild's shared repository cache is a different path with the
same shape — `-disablePackageRepositoryCache` applies the same
belt-and-suspenders; verified present in `xcodebuild -help`.

## 6. Retry — signature-gated bash loop, no supervisor

**Chosen: a shared composite action whose bash loop retries — FR-005's
three attempts total — only when the
attempt's output matches a fetch/transport signature; the caller's
`timeout-minutes` bounds the step.** The step timeout bounds the *whole
loop*, not each attempt — per-attempt kills inside a loop need exactly the
process supervision this design rejects. Sizing: 30 minutes ≈ the
per-attempt-10-min × 3 precedent of mainstream retry tooling (nick-fields/
retry's `timeout_minutes` is per-attempt) and sits comfortably over the
~21-min worst-legit path (one incident-scale ~10-min crawl + ~1 min of
backoffs + two ~5-min retries); 15 was implicitly sized for a single
attempt and could cut a slow-but-real run's retries short. Two composition
details surfaced in review: **the signature set FR-005 owns must carry both
the incident-observed text** (`Recv failure: Operation timed out`) **and git's
own `lowSpeed` abort text** (`Operation too slow…`) — the auth step's
`lowSpeed` limits manufacture exactly that failure mode, and a signature missing it
turns designed crawl-kills into unretried failures; and the retry's
`.build` wipe also re-downloads the Tuist binary, an HTTPS release-asset
fetch the git header can't authenticate (a different channel than the
clone quota — bounded per-attempt re-download, accepted residual). One
more deliberate scope edge: `Project.swift`'s `.remote` deps (swift-tor,
plus swift-clocks and its transitive closure) resolve under xcodebuild's
SourcePackages — inside auth + cache-flag
scope but outside the retry loop, which wraps dedicated fetch steps only.
The
30-min step bound also collided with `tuist-apps`' job-level
`timeout-minutes: 45`: worst-legit 30-min generate + ~20 min of
build/test/upload would be *cancelled* at the cap rather than failed — the
job cap rises to 75 in the same PR (`flake-hunt`'s 120 is already fine;
other jobs lack a cap — plan.md's deferred item has the authoritative
list). Rejected, in detail:

- **RELIABLE-CLONE's embedded perl supervisor** — forked the command into its
  own process group and TERM→KILL'd recorded pgids (macOS ships no
  `timeout`/`gtimeout`). Its one load-bearing job — bounding a never-dies
  crawl — is covered declaratively by `steps[*].timeout-minutes` plus git's
  own `http.lowSpeedLimit`/`lowSpeedTime` aborts; the rest (reparented-orphan
  pgid tracking) is correctness insurance for a path the bounded design
  doesn't take. Cost was a ~60-line perl program the maintainer can't review.
- **`nick-fields/retry` (570★, the de-facto standard)** — has per-attempt
  `timeout_minutes`/`timeout_seconds`, but `retry_on` supports only
  any/timeout/error/exit-code: **no output-signature gate**, so a
  deterministic manifest failure would burn all attempts. Its per-attempt
  kill path is also where its bugs live — #114 documents a failed
  process-kill (EPERM) aborting the whole run, the exact supervision
  complexity this design skips. Third-party JS
  action → SHA-pinning + Node dist in the trust surface; repo rules flag new
  third-party actions for review.
- **`Wandalen/wretry.action`** — `retry_condition` is an expression, still
  cannot inspect command output; same third-party cost.
- **No retry at all** — leaves every transport hiccup costing a whole job;
  GitHub's own runner-images repo retries network downloads internally, so
  retry-on-fetch-flake is industry-standard, and the gate preserves
  never-mask.
- **Bash watchdog instead of perl** (`set -m` + background kill) — bounds
  attempts but SwiftPM's clones re-group under their own pgids and escape the
  group kill; orphaned clones then hold `.build/repositories` dirs that can
  fail the next attempt. The step-timeout + `.build`-wipe design gets the
  same guarantees without pgroup bookkeeping.
- **Step-level `retry:` or native GitHub step-retry** — does not exist;
  `steps[*].timeout-minutes` is the only native bound.

## 7. Verify probe — git-trace send-path + extraheader count, warn-only

**Chosen — specified as FR-007: count effective github.com extraheaders inside the workspace with
`--includes` (expect exactly 1), grep a `GIT_TRACE_CURL=1
GIT_TRACE_CURL_NO_DATA=1` `ls-remote` for `Send header: Authorization`
(expect exactly 1), and warn when the probe call itself fails.** Verified
against the local toolchain, not theorized: an anonymous `ls-remote` trace
shows zero `Authorization` lines (the premise), `=> Send header:` is the
real trace prefix, and a simulated repo-local credential file makes a
`--global`-only count read 1 while `--includes` reads 2 — the exact blind
spot. The count
must run inside a checked-out repo because checkout v6 persists its
credential in a separate file pulled in via `include.path` (§4) — a
`--global`-only count reads 1 even while the duplicate sits in the
repo-local file, blind to the exact bug it guards. The trace-grep backs it
up at send time (two headers → two `Authorization` lines) and the
`ls-remote` exit code backs both up at response time (github.com's 400
fails the probe). This checks the layer the action owns — git
actually emitting the header — and the double-header footgun §4 exists to
prevent. Safety: git natively redacts the token (`redact_sensitive_header`
in upstream `http.c`, upstream-tested; the HTTP/2 case-sensitivity leak was
fixed in git 2.34; the `macos-26` image README lists 2.55.0) — but the *stored* value
(`AUTHORIZATION: basic <b64>`) is redacted nowhere outside the trace, so
the action masks both token forms before any git read. Precedent: credentials-configuring
actions verify via real calls where they exist — `aws-actions/
configure-aws-credentials` retries its STS call 12× internally; our real call
is `ls-remote`. Rejected: REST rate-limit probe (ci/github-clone-auth) —
proves the token is accepted, not that git sends the header, so a
misconfigured key passes it; dropping the probe entirely — the bug class is
silent degradation (anonymous and authenticated clones look identical until
throttled), and warn-only annotations are the only signal that doesn't
couple job health to the probe. A third warn-only check — the job token's
write scope via `permissions.push` — is specified and justified in §9.

## 8. Hosting and slicing — local composite actions, six prepare/apply PRs

**Chosen: `./.github/actions/` in this repo, sliced spec → auth-action →
auth-wiring → hardening → retry-action → retry-wiring.** Same-repo actions
are first-party code at the same commit — no SHA-pinning needed even under
strict supply-chain review (per Sentry's gha-security-review taxonomy and
GitHub's secure-use reference, which reserves immutable pinning for
third-party `uses:`). The prepare/apply split is the feature-flag pattern at
PR granularity — mechanism lands dark, wiring proves it. Rejected: a shared
`21-DOT-DEV/actions` repo today — correct shape once a second org repo
consumes (siblings run the same anonymous-fetch CI), but it adds @v1 release
process for one consumer and org-repo creation is an ask-first boundary;
the action directories are already self-contained for the later move.
Per-workflow PR splitting — five identical-pattern diffs, ceremony without
isolation since the shared action file is the real revert unit. One big PR —
the RELIABLE-CLONE shape this spec exists to correct.

## 9. Token scope — write-scoped jobs excluded, warn-guard as tripwire (FR-008)

**Chosen: exclusion by wiring + a warn-only `permissions.push` check in the
action.** Spec review surfaced that `docc-release.yml`'s `release` job holds
`contents: write` (for `gh release upload`) while fetching nothing — wiring
auth into it would persist a write-scoped token in `~/.gitconfig` for the
job's whole run with zero benefit (OWASP names write-scoped `GITHUB_TOKEN`
exfiltration a primary threat; actions/checkout#485 documents that a
persisted credential hands every later step implicit token access). That
job is excluded; its checkout is deleted outright — every step in it is
API- or env-driven (`gh release upload`, `download-artifact`, version
echoes), so the checkout's only effect today is persisting the write token
via checkout's repo-local credential. Runtime detection is heuristic by necessity: GitHub
exposes no token-permission introspection endpoint (security tooling like
`patdown` exists specifically to probe that gap), so the action warns when
`gh api repos/{repo}` `permissions.push` reports true — the repo object's
`permissions` field is the effective-permission proxy. Fidelity for a
job-scoped token is verified on the T008 branch by temporarily granting a
throwaway job `contents: write`; if the field proves unreliable, the
exclusion and pairing rule stand alone — the check degrades to a missed
annotation, never a failure. Review added two edges: installation tokens
may omit `permissions` entirely, and the API call itself can fail on a
flaky network — either way the outcome is an inconclusive `::notice::`,
never a misleading `::warning::` (a warning is emitted only on an
affirmative `push == true`). With the checkout gone, `gh release upload`
needs repo context: current `gh` falls back to `GITHUB_REPOSITORY`, but
`GH_REPO` is set explicitly — deterministic across gh versions (cli/cli#3557
added the fallback; the explicit var works everywhere). Review also surfaced
that `development-docs.yml`'s "dependency-free" comment is stale —
`Development/Tools` fetches `swift-yaml` + `swift-argument-parser`, so the
`check` job is fetch-performing and stays inside the auth scope; the
comment is corrected in the same PR.
