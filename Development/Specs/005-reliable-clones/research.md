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
throttle signature: `Fetched …/swift-plugin-tuist.git (569.38s)` is
SwiftPM's git-fetch line (binary artifacts log `Downloading binary
artifact` — absent), and the ~8-minute gap in the log (06:36:22 →
06:44:18) is consistent with a stall a 60-second `lowSpeedTime` would
have cut short — consistent, not proof, since SwiftPM can stay silent
while bytes still flow. Upstream
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
authenticates the clone. Independent precedent: the ACTS project's
[`CI/dependencies/github_auth.sh`](https://github.com/acts-project/acts/blob/main/CI/dependencies/github_auth.sh)
ships the identical mechanism — global
extraheader from `GITHUB_TOKEN`, `--replace-all`, `::add-mask::` on the
base64 — built `base64 | tr -d '\n'` since GNU base64 wraps at 76
chars and token length isn't guaranteed, then masking that exact
string — the same preemptive-header reasoning — settling for a
`/rate_limit` probe that §7's send-path check improves on.

## 3. Delivery — the global config FILE, not environment injection

**Chosen: write `~/.gitconfig`, and select the provider that reads it.**
xcodebuild's package fetcher is a separate code path from the git CLI —
Apple's CI guidance documents `-scmProvider` selecting between Xcode's
built-in SCM tooling and the Mac's git installation — and which config
the built-in path honors is undocumented: on RELIABLE-CLONE a
`GIT_CONFIG_GLOBAL` env redirect was ignored there, which would silently
leave every xcodebuild resolution anonymous while SwiftPM's shell-outs
kept working. Two-layer answer: the FILE covers every reader that honors
config at all, and `-scmProvider system` on every resolving invocation
(T005's flags, T007's manifest args for the internal call) removes the
built-in path from the equation — selection, not a default-provider
assumption (tuist/tuist#8099's canonical example for
`additionalPackageResolutionArguments` is the same flag; polpiella's
[production CI](https://www.polpiella.dev/private-swift-packages-on-ci-cd/)
relied on global-config rewrites reaching xcodebuild's
clones — evidence only the system path provides; the
[Swift Forums thread](https://forums.swift.org/t/support-for-resolving-private-packages-through-https-with-xcodebuild/48581)
corroborates the reach via `insteadOf` rewrites, though its report that
`system` has been the default provider since 12.5 is contradicted by the
RELIABLE-CLONE observation above — a redirect system git would have
honored was ignored — the conflicting accounts themselves being the
case for selection over assumption). `GIT_CONFIG_COUNT`
inline config still doesn't cover every reader — file delivery stays the
uniform choice. Cost accepted: the token sits in `~/.gitconfig` for the
job's life (composite actions cannot register post steps) — acceptable on
ephemeral hosted runners with a `contents: read` token on a public repo,
enforced by keeping write-scoped jobs out of the wiring (§9); explicitly
documented do-not-use on self-hosted runners. A side benefit of the
provider selection: under `system` the xcodebuild-side fetches ARE git —
`http.lowSpeed*` applies unconditionally, closing the earlier caveat that
a built-in fetcher might honor only a subset of http settings. (Xcode
16's `-packageAuthorizationProvider netrc|keychain` targets the
registry/artifact-download channel — still rejected: the graph's one
binary target, swift-plugin-tuist's `tuist.artifactbundle.zip`, is a
public release asset needing no auth, and the git config can't reach
that channel anyway.)

## 4. Pairing — `persist-credentials: false` wherever auth runs

**Chosen: required, not optional.** checkout's default persists a repo-local
github.com credential — as of v6, in a *separate file* under
`$RUNNER_TEMP` pulled in by an `includeIf "gitdir:…"` directive the repo's
config carries (checkout#2286), not written into `.git/config` directly —
which combined with the global extraheader sends TWO `Authorization`
headers and github.com answers a bare `400 Duplicate header` — reproduced
locally on RELIABLE-CLONE. With persistence off, the global header is the
only one and covers in-repo commands too. The separate-file detail also
decides where the count check must look: inside the workspace with
`--includes`, because a `--global`-only count is blind to it (§7).
Ordering matters equally: a
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
-C`s into and cannot re-enter — and the log's `skipping cache due to
an error` shows SwiftPM had already abandoned the cache entry itself,
so the fatal came from its own bookkeeping after that fallback, the
exact path the flag removes. `swift test`, `swift run`, and
`generate-documentation` resolve through the same shared cache — leaving
the flag off them would close the crash path in 2 of ~8 fetch points while
claiming the whole thing. The flag costs nothing on a fresh runner (the
cache starts empty) and is accepted by `swift test`/`build`/`run` (verified
on the current toolchain; plugin subcommands take it as a `swift package`
option). The Dockerfile `RUN` lines are `swift`-family steps too — the flag
is a plain CLI arg, so it reaches in-container where the git config cannot.
xcodebuild's shared repository cache is a different path with the
same shape — `-disablePackageRepositoryCache` applies the same
belt-and-suspenders; verified present in `xcodebuild -help`. The one
resolve no workflow flag can reach — the `xcodebuild
-resolvePackageDependencies` `tuist generate` runs internally — gets it
through the manifest pass-through described in §6.

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
attempt and could cut a slow-but-real run's retries short. The
signature-gated shape isn't foreign to this repo — `tuist-apps`'s iOS
rows already re-run `test-without-building` up to 5× gated on a
launch-crash signature (documented in `.github/AGENTS.md`), so the
action generalizes an in-repo precedent rather than importing a new
retry philosophy. Two composition details surfaced in review: **the signature set FR-005 owns must carry both
the incident-observed text** (`Recv failure: Operation timed out`) **and git's
own `lowSpeed` abort text** (`Operation too slow…`) — the auth step's
`lowSpeed` limits manufacture exactly that failure mode, and a signature missing it
turns designed crawl-kills into unretried failures; and the retry's
wipes re-download `swift-plugin-tuist`'s `tuist.artifactbundle.zip` —
`.build` on the plugin fetch, the SourcePackages wipe inside every
resolve attempt — an HTTPS release-asset fetch the git header can't
authenticate and a channel `http.lowSpeed*` doesn't govern either: a
stalled artifact download prints no git-transport signature, so it exits
unretried at the step bound (bounded per-attempt re-download plus a
signature blind spot — accepted residual, since guessing its failure
text would widen the regex on words nobody has observed).

**Loop plumbing.** Three review-surfaced details keep the loop honest:
the `command` input reaches the script through `env:` — never inline
`${{ inputs.command }}` in `run:`, the script-injection pattern
GitHub's own docs warn against — and runs as `bash -eo pipefail
-c "$CMD"` since `bash -c` doesn't inherit the composite `shell:
bash` flag (a multi-line command would otherwise keep going after a
failed line); the attempt's real exit code is `PIPESTATUS[0]`,
captured as the branch's first statement — inside `if ! cmd | tee`,
`$?` is the `!`'s result, always 0, and a non-network failure would
exit 0 green (verified on-machine, not speculated); and the action
exposes an `attempts` output — `uses:`-wrapped stdout isn't
capturable and `$GITHUB_STEP_SUMMARY` is per-step, so the output is
the channel the selftest asserts on — while an attempt-2+ success
also emits `::warning::` plus a summary line, the Bazel `FLAKY`
precedent: a retried-then-green run gets reported, not hidden.

**The internal-resolve edge.** One scope edge review surfaced:
`Project.swift`'s `.remote` deps (swift-tor, swift-clocks and its
transitive closure) plus the whole root-package graph the
`.package(path: "..")` entry brings — `developmentDependencies` on
untagged refs included, swift-plugin-tuist's artifact bundle among
them — resolve through
an `xcodebuild -resolvePackageDependencies` `tuist generate` runs
internally — passed no `-derivedDataPath`, so the clones land in Xcode's
default global DerivedData while the builds read `.derivedData`
(tuist/tuist#2712 documents the split; EnviousWispr's CI postmortem —
[issue](https://github.com/saurabhav88/EnviousWispr/issues/1295),
[PR](https://github.com/saurabhav88/EnviousWispr/pull/1300) —
measured ~90–100 s of duplicated resolution per lane from exactly it) —
meaning `build-for-testing` was re-cloning the remote graph *unretried*.

**The redirect: env-gated manifest args.** The fix is a redirect, not
another step: `Tuist.swift`'s
`generationOptions.additionalPackageResolutionArguments` appends
`-scmProvider system`, `-clonedSourcePackagesDirPath <abs path>`, and
`-disablePackageRepositoryCache` to that internal call — but only when a
`TUIST_`-prefixed variable supplies the path (tuist/tuist#8099 added the
pass-through as the supported replacement for the deprecated
`resolveDependenciesWithSystemScm` and the dedicated
`clonedSourcePackagesDirPath` case tuist/tuist#3628 had introduced —
the raw-args form is the supported one, confirmed against upstream
history;
tuist/tuist#1183's `Environment` reads `TUIST_*` variables — the
always-forwarded prefix: 4.195's `manifestEnvironment` option could name
extra variables, but it lives inside `Tuist.swift` itself, so it cannot
forward a variable to its own evaluation — the prefixed var is the only
channel that exists at that point in time). One caveat the docs do not
settle: the variable crosses several hops the docs never enumerate —
runner env → the `swift package` host → the plugin process (which
spawns `tuist` via `Process()` with only `executableURL` +
`arguments` — no `environment` set; verified in the vendored plugin
source — so it inherits)
→ `tuist` → manifest evaluation — and the forwarding list names only
the project manifests and helpers, so whether `Tuist.swift`'s own
evaluation sees the variable is confirmed by the every-run pin-check
rather than assumed from docs.

**Placement, defaults, and the local gate.** The file lands at the repo
root, not `Projects/`: Tuist's root locator treats `Tuist.swift` as a
marker alongside `Tuist/` and `.git` (community thread
[t/107](https://community.tuist.dev/t/migrate-tuist-config-swift-to-tuist-swift/107),
PRs [622](https://github.com/tuist/tuist/pull/622)/[1319](https://github.com/tuist/tuist/pull/1319)),
so inside `Projects/` it would relocate the root — and every
root-relative lookup — there; beside `.git` the root is unchanged by
construction. The gate matters because a committed manifest also
shapes *local* `tuist generate`: unconditional, it would pay the
whole-graph re-clone — shared cache disabled — into a repo-local
directory no local Xcode reads, when the default-DerivedData resolve it
replaces is one the developer's Xcode open actually reuses. A subtler
cost is what a *bare* `Tuist.swift` does before the gate is even read:
constructing `Tuist(...)` swaps the no-file defaults for
`.options(...)`'s struct defaults (`disableSandbox: true`,
`defaultSwiftVersion: "5"`, `onOutdatedDependencies: .warn`, …) —
docs-identical on paper, but nobody has diffed them, so T007 carries a
local step: `tuist generate` with and without the file (variable unset)
and diff the generated `project.pbxproj` by hand — the generated
project is gitignored, so there is no committed artifact to compare
against — which catches generation-visible drift; knobs that don't
surface in the project file (`onOutdatedDependencies`, sandboxing) are
docs-assumed, not verified.

**What CI observes and what stays conditional.** CI sets the
variable to `${{ github.workspace }}/.derivedData/SourcePackages` —
absolute, so the internal resolve's working directory stops mattering —
and the builds' `-derivedDataPath` finds the fetch warm: resolved once
inside the retried step and reused rather than re-cloned — *if* the retry
truly covers the internal resolve, which rests on `tuist generate`
propagating its exit code and fetch output rather than summarizing them
away; T008's forced-failure case is the evidence, and the claim stays
conditional until observed. A second canary closes §3's reachability
question the same way — a deliberately wrong extraheader must *break*
the resolve production actually performs; a still-succeeding anonymous
clone would prove the chain never read the config. The recipe matters:
the job mirrors production — checkout with `persist-credentials: false`,
the real auth step, `TUIST_CLONED_SOURCE_PACKAGES_DIR` set as the app
workflows set it — and generate runs under the real auth first, its
pin-check asserting the pinned dir's `checkouts/` is non-empty
(`repositories/` collects skeletons even on a failed resolve, so
top-level non-empty can't distinguish a fetch from a corpse) — proving
the env-var hops, the
`additionalPackageResolutionArguments` propagation, and the
pin all work; then `--replace-all` swaps a bogus value into the same
`http.https://github.com/.extraheader` key the auth action writes, an
`ls-remote` against the repo's own remote fails first (control), the
pinned dir alone is wiped, and the same `tuist generate` is re-run.
The re-run is the real call rather than a copy of it: a hand-invoked
xcodebuild would only prove system git reads `~/.gitconfig`, while the
re-run tests arg-propagation and provider selection together. Read the
result by the log and `checkouts/`, not the exit code alone: an
auth-shaped fetch error in the workspace-resolve phase is a pass;
green with `checkouts/` repopulated means an anonymous clone succeeded and
the chain ignores the config; green with it still empty means the
resolve never ran — inconclusive, investigate. Run one's plugin phase
left `.build` warm, so run two's plugin resolution fetches nothing —
a failure there means the warm-resolution assumption broke. With a
bogus header from the start, generate's plugin-phase `.build` clone
would fail first and the resolver under test would never run.

**Cleanup, signals, and residual bounds.** The same args carry
the cache flag a workflow
step could never attach to that call. `cleanup-dirs` for generate becomes
`.build` + `${{ env.DERIVED_DATA }}/SourcePackages` — the runner expands
the expression before the action sees it, so the pin and the wipe share
the one env definition rather than drifting; a pin or
env-var regression announces itself on *every* run — the post-generate
step warns whenever `checkouts/` is absent or empty — with
the cleanup's absent-path warning still covering the retry path and
`Fetching` lines in downstream logs as the last resort. Wrapped
xcodebuild steps
elsewhere still pin their clone state to a fixed repo-local path with
`-clonedSourcePackagesDirPath` — the knob Fastlane exposes as
`cloned_source_packages_path` for exactly this job; fastlane/fastlane#16986
confirms `-derivedDataPath` is honored on `-resolvePackageDependencies`
too, but the purpose-built flag is the explicit form. One input-shape
detail carries weight: entries reach the script as plain text and are
taken literally — `~`, `$HOME`, `$VAR` are never expanded, so a stray
one lands inside the workspace and warns as absent rather than
expanding somewhere the guard would refuse anyway — and an entry that
names nothing warns rather than skips silently, since a misspelled path
would quietly disable half the wipe. The dedicated resolve
steps themselves are the industry shape — retry the install step, never
the suite: `npm ci` removes `node_modules` itself before installing, and
the canonical bundler flake recipe is `rm -rf vendor/bundle && bundle
install`. The
30-min step bound also collided with `tuist-apps`' job-level
`timeout-minutes: 45`: worst-legit 30-min generate + ~20 min of
build/test/upload would be *cancelled* at the cap rather than failed — the
job cap rises to 75 in the same PR (docc-release's `docc` job likewise
rises 20 → 45 under T010 for the same arithmetic; `flake-hunt`'s 120 is
already fine; the rest lack caps — plan.md's deferred item has the
authoritative list). Rejected, in detail:

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
- **`actions/cache` on the shared SwiftPM cache or SourcePackages** — the
  standard JS-ecosystem move, harmful here: it would persist exactly the
  poisoned-cache state (swift-package-manager#9037) across runs instead of
  clearing it. The design disables the cache, not preserves it.
- **`-disableAutomaticPackageResolution` / `-skipPackageUpdates` on the
  downstream xcodebuild steps** — Apple's documented CI pairing, adopted
  in review and rejected on the corrected mechanism and corrected fact:
  the first pins resolution to the resolved file rather than suppressing
  the fetch (whether a missing checkout still clones under it is
  untested), and while the root `Package.resolved` is gitignored —
  leaving apple-builds' root-package builds nothing to pin against —
  `Projects/.package.resolved` is committed — the workspace graph's
  resolved file — so the app jobs alone could adopt it. The second
  ("skip updating package dependencies from their remote") is the closer
  fit for "the build must not fetch after a warm resolve", but whether it
  suppresses remote checks, missing-checkout clones, or both is
  undocumented — either adoption is a per-job split waiting on a
  T008-style flag experiment, and both convert a skipped or corrupt
  resolve into a build failure that reads like a pinning error — a
  config-coupling failure mode the resolve steps already narrow.
  Revisit if a mid-build fetch flake is ever observed.

## 7. Verify probe — git-trace send-path + extraheader count, warn-only

**Chosen — specified as FR-007: count effective github.com extraheaders
inside the workspace with
`--includes` (expect exactly 1), and in a `GIT_TRACE_CURL=1
GIT_TRACE_CURL_NO_DATA=1` `ls-remote` compare case-insensitive `=> Send
header: authorization:` lines against `=> Send header: (GET|POST) `
request lines — equal AND ≥ 1 — warning also when the probe call
itself fails.** Verified against the local toolchain, not theorized:
an anonymous `ls-remote` trace shows zero `Authorization` lines (the
premise), `=> Send header:` is the real trace prefix, and a simulated
repo-local credential file makes a
`--global`-only count read 1 while `--includes` reads 2 — the exact
blind spot. Traced on git 2.54: `ls-remote` sends two requests (GET
`info/refs`, POST `git-upload-pack`) so a single configured header
prints twice — "expect exactly 1" reports a duplicate on every healthy
run; git logs the header name exactly as configured (`AUTHORIZATION:`)
so a case-sensitive grep reports it missing; and HTTP/2 adds `== Info:
[HTTP/2] [n] [authorization: …]` lines so a loose grep counts four —
equal-counts-plus-≥1 is the only shape that's right in all three. The count
must run inside a checked-out repo because checkout v6 persists its
credential in a separate file pulled in via an `includeIf "gitdir:"`
directive (§4) — a
`--global`-only count reads 1 even while the duplicate sits in the
repo-local file, blind to the exact bug it guards. The trace-grep backs it
up at send time (two headers → two `Authorization` lines) and the
`ls-remote` exit code backs both up at response time (github.com's 400
fails the probe). This checks the layer the action owns — git
actually emitting the header — and the double-header footgun §4 exists to
prevent. Safety: git natively redacts the token (`redact_sensitive_header`
in upstream `http.c`, upstream-tested; the HTTP/2 case-sensitivity leak was
fixed in git 2.34; the `macos-26` image README lists 2.55.0 — the PATH
git the probe and SwiftPM's clones invoke; `-scmProvider system` has
xcodebuild call the git it resolves, and both read `~/.gitconfig`
through the URL-scoped key) — but the *stored* value
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

## 8. Hosting and slicing — local composite actions, seven prepare/apply PRs

**Chosen: `./.github/actions/` in this repo, sliced spec → auth-action →
auth-wiring → hardening → retry-action → retry-wiring → dedicated-resolve
wiring.** Same-repo actions
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
comment is corrected in the same PR. The runtime guard still sees only
the job that runs it — the mechanical form is static: FR-009's lint
job in the ubuntu-only `workflow-lint` workflow (triggered on
`.github/workflows/**`, `.github/actions/**`, and
`.github/actionlint.yaml`, alongside `actionlint` + `shellcheck`) parses
the workflows at PR time and fails on a
`github-git-auth`-using job with a write-capable effective permission
(job `permissions:` else the workflow's; any write value or
`write-all` — and no block at either level fails too, since the token
then inherits the repo default, which may be write), a checkout
without `persist-credentials: false`, or a
checkout ordered after the auth step. The one exemption is
`AUTH_LINT_EXEMPT: "<reason>"` on the job — it lifts only the
write-scope rule (the checkout checks still apply) and fails the lint
in any file but `actions-selftest.yml`, the home of the deliberate
FR-008 canary. The job lands in PR 3 beside the
wiring it checks — in PR 2 no job uses the action yet, so it would
pass trivially — and the runtime warn-guard stays as backup for what
static parsing cannot see.
