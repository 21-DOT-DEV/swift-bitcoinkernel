# Tasks — 005 · Authenticate github.com clones and retry fetch flakes in CI

Ordered work for [the plan](./plan.md); requirements cited as `FR-NNN` from
[spec.md](./spec.md); rationale in [research.md](./research.md).

## Phase 0 — The plan itself

- [x] T001 This spec and the regenerated specs index ·
  `Development/Specs/005-reliable-clones/{plan,spec,tasks,research}.md`,
  `Development/Specs/README.md`

**Checkpoint:** `swift run --package-path Development/Tools plans --check`
is green; the index lists feature 005.

## Phase 1 — The auth mechanism, inert

- [x] T002 `github-git-auth` composite action: global
  `http.https://github.com/.extraheader` from a `token` input — mask BOTH the
  raw token and its base64 form per FR-001 (the encoded value is what sits
  in the config; anything echoing `git config` otherwise leaks it) — masking runs
  before any git read/trace, covering the paths git doesn't control
  (`git config` output, step logs; git's own trace already redacts the
  value via `redact_sensitive_header`) — written with
  set semantics not `--add` so a re-run keeps the count at 1 —
  `http.lowSpeedLimit`/`lowSpeedTime`, and a warn-only verify step per
  FR-007/FR-008 (the conditions those requirements own) (FR-001, FR-007,
  FR-008) · `.github/actions/github-git-auth/action.yml`
- [ ] T009 `actions-selftest` workflow (runs on PRs touching
  `.github/actions/**` *or the workflow file itself* — a path filter that
  excludes `actions-selftest.yml` would leave its own edits unchecked —
  matrix over `macos-26` *and* `xcode-27`, the two runner labels the
  actions actually serve: their git-version-dependent behavior is the
  thing under test) with the auth
  smoke case: `uses:` the auth action
  on a real runner, then asserts FR-001/FR-007 observables — effective
  `--includes` count of 1 and, in a step-scoped `GIT_TRACE_CURL`
  `ls-remote`, `=> Send header: authorization:` lines matching the
  `=> Send header: (GET|POST) ` request-line count with the request
  count ≥ 1 — "expect exactly 1" fails in both directions (git 2.54
  emits two requests — GET `info/refs`, POST `git-upload-pack` —
  logs the header name exactly as configured, and HTTP/2 adds `==
  Info:` copies).
  A second job granted `contents: write` asserts the FR-008 warning
  fires — gated on `head.repo.full_name == github.repository` so it
  runs only where the grant can take effect (fork tokens stay
  read-only regardless of the block, and an unconditional job would
  red every fork PR) — and carries `AUTH_LINT_EXEMPT` with a reason
  so FR-009's write-scope rule doesn't flag the deliberate exception
  (the checkout checks still apply to it). Its own
  checkout follows the FR-002 pairing it exercises.
  Workflow-level `permissions: {}` + job `contents: read` per the repo's
  least-privilege convention. Before these assertions are written, a
  throwaway scratch run settles two unknowns: `gh api repos/{repo}
  --jq .permissions` in one read-scoped and one write-scoped job —
  if the field is absent for a `GITHUB_TOKEN`, the canary assertion
  degrades per research §9 rather than blocking the PR — and a stub
  composite action whose inner step writes `attempts` to
  `$GITHUB_OUTPUT` then exits nonzero, read by a later
  `if: always()` step through `steps.<id>.outputs`, proving composite
  outputs publish across an inner failure (T006's negative cases
  depend on it).
  `.github/actionlint.yaml` gains `self-hosted-runner.labels:
  [xcode-27]` (a custom label actionlint's built-in list doesn't know
  — verified: `runner-label` errors on `flake-hunt:45` and the four
  `tuist-apps` matrix rows); the file already exists — created in the
  T003 PR carrying the `paths:`/`ignore:` for `docc-release.yml`'s two
  `uses: $/…` lines (actionlint ≤1.7.12 can't parse `$/`; drop that
  block once a pinned release ships `rhysd/actionlint#732` — its known
  gap: the ignore also hides the `$/` step's input check, and a
  missing `token` is caught by neither lint nor runner — it surfaces
  as clone failures downstream). Also,
  two pre-existing findings are fixed so the gate is green: drop the
  always-empty `${{ matrix.suffix }}` from `tuist-apps:13` (renders
  identical names) and resolve `docc-release:195`'s SC2012 (fixed known
  path — a `# shellcheck disable` comment, not a `find` rewrite). Lands
  inside PR 2 — workflow commit pushed alone first so CI observes red
  with the action missing (CI only ever tests the tip; one push of both
  commits never shows red), action commit second (green) — plus the
  `.github/AGENTS.md` inventory row (verifies FR-001, FR-007
  mechanically) · `.github/workflows/actions-selftest.yml`,
  `.github/actionlint.yaml`, `.github/AGENTS.md`,
  `workflows/{tuist-apps,docc-release}.yml` (lint fixes). Also the
  code-side pilot: run the Specs-README delta sweep on this PR's diff
  before it merges and record whether it caught anything the executable
  gates missed — that result decides if the rule earns a
  `.github/AGENTS.md` variant
- [ ] T011 `workflow-lint` workflow — ubuntu-only, triggered on
  `.github/workflows/**`, `.github/actions/**`, and
  `.github/actionlint.yaml` (so every workflow edit is linted and its
  own edits re-trigger it) — running `actionlint` and `shellcheck`
  over the workflows and the actions' scripts, so quoting/`errexit`
  mistakes are linted rather than learned by live failure. No brew on
  ubuntu: `actionlint` installs from a pinned release tarball with a
  checksum check, `shellcheck` from the distro package; if a newer
  lint rule ever fails an unrelated diff, pin the versions then. The
  `$/` suppression already lives in `.github/actionlint.yaml` (shipped
  in the T003 PR), so this job needs no pinned-version workaround.
  `permissions: {}` at the workflow level, `contents: read` on the
  jobs. T004's FR-009 job lands here with the file — it couldn't ride
  the T003 PR because this file didn't exist yet (FR-009
  pending) · `.github/workflows/workflow-lint.yml`

## Phase 2 — Turn auth on everywhere packages are fetched

- [x] T003 Add `persist-credentials: false` to every checkout and the
  `github-git-auth` step immediately after it, in every fetch-performing job
  across all five macOS workflows — except `docc-release.yml`'s `release`
  job, which fetches nothing and holds `contents: write`; that job's unused
  checkout step is deleted instead, with `GH_REPO: ${{ github.repository }}`
  added to its env so `gh release upload` resolves the repo without one.
  Same PR corrects the stale comments in `development-docs.yml` —
  "dependency-free" (the checker fetches `swift-yaml` +
  `swift-argument-parser`, so `check` is a fetch job and gets auth) and
  "private repository" (the repo is public)
  (FR-001, FR-002) · `.github/workflows/{apple-builds,development-docs,
  docc-release,flake-hunt,tuist-apps}.yml`
- [ ] T004 Record the pairing rule (FR-002 and its edge cases — the
  mechanisms, and auth *after* every checkout) in `.github/AGENTS.md`;
  `docker-builds` and the write-scoped `release` job are the documented
  exceptions, and a `$/`-reference variant covers jobs whose checkout
  uses an explicit `ref:` differing from the workflow's commit. The
  prose half shipped in the T003 PR — rule, exceptions, `$/` variant,
  and the "private repos" → least-privilege tightening (the rule is
  least-privilege generally; the repo is public). The box stays open
  for the mechanical half, which lands with T011's file: the FR-009
  job fails a PR when a
  job using `github-git-auth` carries a write-capable effective
  permission (the job's `permissions:` block if present, otherwise the
  workflow's; any write value or `write-all` counts — and no block
  declared at either level fails too, since the token then inherits
  the repo default), a checkout
  without `persist-credentials: false`, a checkout ordered after
  the auth step, or an `AUTH_LINT_EXEMPT` marker outside
  `actions-selftest.yml` — implemented with `yq` (preinstalled on
  `ubuntu-latest`; pinned tarball if ever absent) (FR-002,
  FR-009) · `.github/AGENTS.md`,
  `.github/workflows/workflow-lint.yml`

**Checkpoint:** every fetch-performing macOS job's log shows the "github.com
git requests carry the Authorization header" line after checkout.

## Phase 3 — Close the fatal cache path and bound the fetch

- [ ] T005 Add `--disable-dependency-cache` to every `swift`-family step
  that resolves packages (the `tuist generate` calls, `swift
  test`/`run`/`build` — docc-release's `build` job runs `swift build` —
  `generate-documentation`, and the Dockerfile `RUN` lines — the flag is a
  plain CLI arg that reaches in-container where clone auth cannot),
  `-disablePackageRepositoryCache` and `-scmProvider system` on every
  xcodebuild invocation in each auth-using job — `build`,
  `build-for-testing`, `test-without-building` alike: the flags are
  global and inert where unused, and any action that loads package
  state can trigger a drift-resolve, so uniform coverage beats a
  per-action guess (the provider flag pins them onto the git that
  reads the config file; the internal resolve inside `tuist generate`
  is reached separately by T007's manifest args, the one call a
  workflow flag cannot attach to),
  `timeout-minutes: 30` to the generate steps,
  and raise the `tuist-apps` job cap 45 → 75 so the worst-legit retry path
  fits under it (FR-003, FR-004) ·
  `.github/workflows/{apple-builds,development-docs,docc-release,flake-hunt,
  tuist-apps}.yml`, `Dockerfile`

**Checkpoint:** a `tuist generate` log shows clones writing under
`.build/repositories`, not `~/Library/Caches/org.swift.swiftpm`.

## Phase 4 — The retry mechanism, inert

- [ ] T006 `retry-on-fetch-flake` composite action: bash loop gated on the
  signature table FR-005 owns —
  the `command` input reaches the script through `env:` (never inline
  `${{ inputs.command }}` in `run:` — the script-injection pattern
  GitHub's docs warn against), and each attempt runs
  `bash -eo pipefail -c "$CMD" 2>&1 | tee log` — `-e` explicit since
  `bash -c` does not inherit the composite `shell: bash` flag, so a
  multi-line command still dies on its first failed line — with
  `rc=${PIPESTATUS[0]}` captured as the branch's FIRST statement: inside
  `if ! cmd | tee log`, `$?` is the `!`'s result — always 0 — so a
  non-network failure would exit 0 and go green, the exact silent pass
  the design forbids (verified on-machine) —
  ≤3 attempts, linear backoff, the directories FR-006 names wiped
  between attempts (`cleanup-dirs` input — entries arrive one per line
  and are read `while IFS= read -r p || [[ -n $p ]]`, so no
  word-splitting, no globbing, and no silently dropped unterminated
  last line (a `|-` scalar strips it): a literal `*` is a path named
  `*`, not a match — then judged by FR-006's guard verbatim: taken
  literally (no `~`/variable expansion), normalized to an absolute path
  strictly inside `$GITHUB_WORKSPACE` or `$RUNNER_TEMP` — both roots
  canonicalized the same way first — existing
  entries through symlinks; for a missing one the deepest existing
  ancestor goes through symlinks and only its tail is lexical (macOS
  `realpath` has no `-m`, so this walk is hand-written) —
  `rm -rf`'d when present, `::warning::` when absent; default
  `.build`) —
  real exit code on non-signature failures; the action exposes
  `attempts` and `exit_code` outputs — the machine-readable channel the
  selftest asserts on (`uses:`-wrapped stdout isn't capturable,
  `$GITHUB_STEP_SUMMARY` is per-step, and a step's exit code isn't
  readable by later steps either) — each written to `$GITHUB_OUTPUT`
  before EVERY terminal `exit` — success, non-signature bail,
  exhausted attempts; the deliberately-failing cases run
  `continue-on-error: true` on the wrapped step with assertions on
  `steps.<id>.outcome` under `always()` — `'failure'` on the negative
  cases AND `'success'` on the positives, since continue-on-error
  forces conclusion to success and outcome is the only real signal —
  and the scratch-run pre-flight in T009 proves composite outputs
  publish across an inner failure before these cases are written; an
  attempt-2+ success also
  emits `::warning::`
  and a summary line so retry frequency is measurable — and PR 5 also
  extends the
  selftest with fake-command cases covering FR-005's whole table: one
  printer row per retryable signature → retried; `RPC failed; HTTP
  403` → exactly one attempt (the auth-precedence check); silent
  exit-3 → `outputs.attempts == '1'` with code 3; and a counter-file
  case — attempt 1 prints `Recv
  failure` + exits 1, attempt 2 exits 0 → `outputs.attempts == '2'`,
  the step green — the `::warning::` is log-observed, not
  step-asserted (the reason `attempts` exists) — the permanent SC-002
  retry-then-success evidence (a real
  forced timeout can't demonstrate it: `lowSpeed` is global and would
  abort every attempt; the counter and the per-attempt log live in
  `$RUNNER_TEMP` — inside `cleanup-dirs`, FR-006's wipe would reset them
  and the case could never pass) — plus `cleanup-dirs` guard cases:
  entries `/`, `../..`, `a/../..`, bare `~`, `*`, and a symlinked parent
  pointing outside the trees warn and skip with
  nothing deleted, while a trailing `/` normalizes in place and a
  two-entry input with no trailing newline still processes both —
  covering the escape guard and the hand-written normalization on every
  edit — so the signature set FR-005 owns gets a permanent
  regression check on every future edit — pure
  bash, no supervisor (FR-005, FR-006) ·
  `.github/actions/retry-on-fetch-flake/action.yml`

**Checkpoint:** no production workflow calls the action yet — the
selftest's retry cases exercise it; fetch paths unchanged.

## Phase 5 — Turn the retry on for the fetch steps

- [ ] T007 Wrap the `tuist generate` steps in `retry-on-fetch-flake`
  (label + command inputs; the step keeps its `timeout-minutes` as the outer
  bound), each listing `cleanup-dirs` per FR-006 — root `.build` plus
  `${{ env.DERIVED_DATA }}/SourcePackages` (the runner expands the
  expression before the action sees it, so the pin and the wipe share
  the one env definition rather than drifting) — and add `Tuist.swift` at the **repo
  root**, not `Projects/`: the file is a root marker (Tuist's locator
  treats `Tuist.swift`, `Tuist/`, and a `.git` directory as markers), so
  inside `Projects/` it would relocate the root — and every root-relative
  lookup — to `Projects/`; at the repo root it sits beside `.git` and the
  root is unchanged by construction.
  Its `generationOptions.additionalPackageResolutionArguments` gains
  `-scmProvider system` + `-clonedSourcePackagesDirPath` +
  `-disablePackageRepositoryCache` ONLY when
  `Environment.clonedSourcePackagesDir` is set and non-empty — `DERIVED_DATA` becomes
  absolute (`${{ github.workspace }}/.derivedData`) and the generate
  step's env derives the pin from it:
  `TUIST_CLONED_SOURCE_PACKAGES_DIR: ${{ env.DERIVED_DATA }}/SourcePackages`
  — one definition, no drift (`TUIST_*` is the always-forwarded prefix —
  `manifestEnvironment` can't help here since `Tuist.swift` can't forward
  a variable to its own evaluation — and the absolute
  path removes the internal resolve's working directory from the
  question): a committed unconditional pin would also hit local
  `tuist generate`, paying the full graph re-clone with the shared cache
  off into a directory no local Xcode reads, when the default-DerivedData
  resolve it replaces is one an Xcode open actually reuses. The provider
  flag is the auth half: Apple's docs say xcodebuild's built-in SCM is
  its own tooling and `-scmProvider system` selects the Mac's git — the
  code path that provably reads the config file's `extraheader` —
  so the header reaches the internal resolve by selection, not by a
  default-provider assumption. Each wrapped generate gains a following
  ~3-line invariant step: `$DERIVED_DATA/SourcePackages/checkouts`
  must exist and be non-empty, `::warning::` otherwise — `repositories/`
  collects skeletons even on a failed resolve, so top-level non-empty
  can't distinguish a fetch from a corpse — a pin regression
  announces itself on green runs too, not only on retries where the
  cleanup warning fires. The check also verifies the `TUIST_*` channel
  end-to-end — the variable travels runner env → the `swift package`
  host → the plugin process (which spawns `tuist` via `Process()` with
  only `executableURL` + `arguments` — no `environment` set; verified in
  the vendored plugin source — so it inherits) → `tuist` → manifest
  evaluation, and Tuist's forwarding docs name only the project
  manifests and helpers — every hop confirmed here, not assumed.
  A bare `Tuist.swift` also swaps Tuist's no-file defaults for
  `.options(...)`'s struct defaults (`disableSandbox: true`,
  `defaultSwiftVersion: "5"`, `onOutdatedDependencies: .warn`, …) —
  almost certainly identical, but nobody has checked, so the PR's
  verification includes a one-time local step: `tuist generate` with
  and without the file (variable unset) and diff the generated
  `project.pbxproj` by hand (the generated project is gitignored, so
  there is no committed artifact to compare against). Record the pin
  and the env var in `Projects/AGENTS.md` — a developer exporting it
  locally changes where generate writes — and update its
  CI-reproduction recipe to export `TUIST_CLONED_SOURCE_PACKAGES_DIR`
  matching the recipe's `-derivedDataPath`: a local generate without
  it stays unpinned, so the recipe only mirrors CI if it carries the
  var. Generate
  resolves twice over (SwiftPM's plugin resolution into `.build`, an
  internal `xcodebuild -resolvePackageDependencies` for `Project.swift`'s
  remote packages no workflow flag can reach), so pinned, the workspace
  remotes fetch once inside the retried step and `build-for-testing`
  reuses them — coverage resting on generate propagating the resolve's
  exit code and output, which T008's forced-failure case must observe
  before the claim ships (upstream: tuist/tuist#2712 for the split,
  tuist/tuist#8099 for the pass-through, tuist/tuist#1183 for
  `Environment`); record the
  routing rule — fetch steps retry through the shared
  action, new signatures land there *with a selftest case* (the routing
  rule's maintenance half — a signature added without a case recreates
  the untested-logic gap) (FR-003, FR-005, FR-006) ·
  `.github/workflows/{tuist-apps,flake-hunt}.yml`, `Tuist.swift`,
  `Projects/AGENTS.md`, `.github/AGENTS.md`

- [ ] T010 Dedicated resolve steps under the retry action for the jobs
  whose build/test commands would otherwise fetch in-step — the
  industry pattern: retry the install step, never the suite. A
  `swift package --disable-dependency-cache resolve` step in
  development-docs' `check` (`--package-path Development/Tools`,
  `cleanup-dirs: Development/Tools/.build`), apple-builds' `macos` job
  (root `.build`), and docc-release's `build` job — plus in the `docc`
  job ordered AFTER "Enable development dependencies", since the
  plugin dep does not exist in the graph until the tag is deleted; the
  `docc` job's `timeout-minutes` rises 20 → 45 — a 30-minute step inside
  a 20-minute job dies on the job bound before its own timeout can fire,
  the same arithmetic that raised tuist-apps 45 → 75. An
  `xcrun xcodebuild -resolvePackageDependencies -disablePackageRepositoryCache
  -scmProvider system` step in apple-builds' ios/visionos/tvos jobs —
  matching those jobs' `xcrun` invocation form and running at the
  package root — every new resolve step carrying `timeout-minutes: 30`
  per FR-004's three-attempts-plus-slack bound — every xcodebuild
  invocation in the job gaining an absolute
  `-clonedSourcePackagesDirPath` under `${{ github.workspace }}`, so
  clone state sits at the fixed path `cleanup-dirs` names — the entry
  carrying the same expression the pin flag uses — and the
  build step reads what the resolve step fetched. The app-workflow jobs need no dedicated step —
  T007's manifest pin already lands their workspace fetch inside the
  retried `generate`, where the builds' `-derivedDataPath` finds it warm
  (FR-003, FR-004, FR-005, FR-006) ·
  `.github/workflows/{apple-builds,development-docs,docc-release}.yml`

**Checkpoint:** `Generate workspace` and the dedicated `resolve` steps
invoke the action; logs show the attempt group format.

## Phase 6 — End-to-end validation on a throwaway branch

- [ ] T008 Push a throwaway branch carrying the end state — PR 6 and PR 7
  changes included, so every check below sees them — and observe:

  | Check | Method | Verifies | Pass criterion |
  |---|---|---|---|
  | Token masking | auth step's log | FR-001's masking half | `***` wherever token material would print |
  | Effective header | step-scoped `GIT_TRACE_CURL`/`GIT_TRACE_CURL_NO_DATA` `ls-remote` probe plus an effective extraheader count via `--includes` inside the workspace | FR-001, FR-002, FR-007 | `Send header: Authorization` seen; count exactly 1 |
  | Auth teeth on the real call path | dedicated canary job carrying its own `timeout-minutes` (two generates plus resolves): checkout with `persist-credentials: false` → real auth step → normal `tuist generate` under `TUIST_CLONED_SOURCE_PACKAGES_DIR` → pin-check that `.derivedData/SourcePackages/checkouts` is non-empty → `git config --global --replace-all` swaps a bogus value into the same URL-scoped key → `git ls-remote` on the repo's own github.com remote must fail (control) → wipe only `$DERIVED_DATA/SourcePackages` → re-run the SAME `tuist generate` (the real call — a hand-invoked xcodebuild would prove only what nobody doubts) | the coverage premise behind FR-001's xcodebuild clause | run 2 fails auth-shaped in the workspace-resolution phase — read by log and pinned dir, not exit code alone: green is ambiguous (repopulated `checkouts/` → the chain ignores the config → the canary fails the design; stayed empty → inconclusive, investigate, don't count); a plugin-phase failure means the warm-resolution assumption broke — run one's plugin phase warms `.build` deliberately |
  | Warn-guard | throwaway job temporarily granted `contents: write` | FR-008 | warning fires iff the job's token reports write, including whether the field is present; absent field → `::notice::` |
  | Flag acceptance | `swift test`/`generate-documentation`/xcodebuild in the wired jobs | FR-003 mechanically | all accept their cache and provider flags — the manifest's argument propagation into the internal resolve is the load-bearing half |
  | `.build`-local clones | generate log | FR-003 | clones write under `.build`, not the shared cache |
  | Retry-then-success | counter-file case: attempt 1 signature-fails, attempt 2 exits 0 | FR-005, FR-006 | `outputs.attempts == '2'`, step green |
  | Non-signature exit | forced non-network failure | FR-005 | exits on attempt 1 (`outputs.attempts == '1'`) with the original code |
  | Ordering rule | a checkout deliberately placed after the auth step | FR-002's premise | its own fetch fails with the predicted 400 |
  | `lowSpeed` conversion | absurd `lowSpeedLimit` + tiny `lowSpeedTime` set via step-scoped `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_*`/`GIT_CONFIG_VALUE_*` env | FR-005's signature set | the manufactured abort is retried — env-scoped config reaches every git subprocess and dies with the step (repo-local config never reaches the `.build` clones; `--global` would leak into later steps) |
  | Step bound | a `timeout-minutes: 1` step that `uses:` the retry action — the production shape | FR-004 | the step is killed at the bound |
  | Pin + wipe targets | a generate run records where `Project.swift`'s remote fetch lands; a before/after listing of the runner's default DerivedData | FR-006's premise | clones under `.derivedData/SourcePackages`; default DerivedData shows no new `SourcePackages` (the image may carry content); every listed `cleanup-dirs` entry exists post-expansion — an absent one warns — and the every-run invariant is exercised both ways by toggling `TUIST_CLONED_SOURCE_PACKAGES_DIR` |
  | Internal-resolve coverage | a temporarily unresolvable remote URL in the throwaway `Project.swift` — a DNS failure is already in FR-005's table | the premise behind T007's pin | the wrapped generate exits non-zero with the fetch text in the step log over more than one attempt — the retry truly covers the internal resolve, not just the step's name |
  | No post-resolve fetches | downstream build/test steps in every job that gained a dedicated resolve step, plus the app jobs' `build-for-testing` | FR-004's premise | logs show no `Fetching`/`Cloning`/`Checking out` lines — each job's fetch happened inside retried fetch-only work or not at all |

  · throwaway branch, deleted after

**Checkpoint:** every verification box in plan.md ticked from observed runs.

## Pull-request slicing

| # | Landed | Pull request | Tasks | Changed lines | Depends on |
|---|---|---|---|---|---|
| 1 | [x] | The plan documents | T001 | ~1,450 prose | — |
| 2 | [ ] | `github-git-auth` action, inert + `actions-selftest` + `workflow-lint` workflows + `xcode-27` label config in `actionlint.yaml` + pre-existing lint fixes | T002, T009, T011 | ~190 | — |
| 3 | [ ] | Auth wired into fetch jobs across five workflows, `release`-job checkout removed, pairing rule + `$/` variant in `.github/AGENTS.md`, `actionlint.yaml` created with the `$/` ignore | T003, T004's prose | ~230 | — |
| 4 | [ ] | Cache flags on all fetch steps + `timeout-minutes: 30` + job-cap bump | T005 | ~55 | — |
| 5 | [ ] | `retry-on-fetch-flake` action, inert + selftest retry cases | T006 | ~100 | PR 2 (selftest workflow) |
| 6 | [ ] | Retry wired into the two generate steps + `Tuist.swift` clone-path pin + routing rule | T007 | ~50 | PR 5 |
| 7 | [ ] | Dedicated resolve steps under retry in the remaining fetch jobs + docc job-cap raise | T010 | ~95 | PRs 3, 5 |

Numbered order is the recommended landing sequence.

PR 3 ships before PR 2 by choice: the diff that introduces
`uses: $/…` carries its own lint suppression
(`.github/actionlint.yaml`), and the action's `Verify` step observes
auth in every wired job — warn-only, so it can't turn CI red; T009's
selftest remains the gate that can. Before PR 3 merges, confirm the
Verify output ("exactly 1 effective github.com extraheader" and
"carry the Authorization header") on all four `xcode-27` rows of its
CI run — that observation stands in for T009 until it lands. FR-009's
job moves with T011 since `workflow-lint.yml` doesn't exist yet; PR
3's ~230 lines exceed SC-003's ~150 cap — the overage is comments,
doc text, and this bookkeeping, recorded here rather than trimmed.

PR 4 has no code
dependency and may land in any position — one caveat: PRs 4 and 7 both
touch apple-builds' xcodebuild lines, so whichever lands second rebases
(an adjacent-line conflict, not a design coupling). PRs 3, 5, 6 and 7 must follow their
action or workflow PRs. T008 is validation, not a PR — it runs on a
throwaway branch carrying PR 6 and 7's changes before either merges, and
the branch is deleted after. Between PR 4 and PR 7 the implicit-fetch
steps (`swift test`/`build`, `generate-documentation`) stay unbounded —
a gap that pre-exists this feature, closed when T010's dedicated resolve
steps land; FR-004's bound is measured on the final tree.

Post-landing review amendments to the four documents travel as an
additional prose-only PR outside the numbered sequence — the table
tracks the code-change and validation work.

## Deferred

- Extraction to a shared `21-DOT-DEV/actions` repository when a second org
  repo adopts — self-contained directories already; blocked only on a real
  consumer, not design.
- `docker-builds` in-container clone auth — a small BuildKit secret mount
  (`RUN --mount=type=secret` feeding `GIT_CONFIG_COUNT`) would do it;
  deferred for scope, not size.
- Retry wiring for build/test steps that re-resolve mid-step (`swift
  build`/`test`, the app jobs' `xcodebuild` runs) — retrying them
  re-runs build/test work, not just
  the fetch; their coverage is auth + the widened cache flags, plus warm
  reuse for the app jobs under T007's clone-path pin.
- Job-level `timeout-minutes` on uncapped jobs — see plan.md's Deferred
  work item for the authoritative job list; a pre-existing gap — the
  caps that change here are `tuist-apps`' (45 → 75, T005) and
  `docc-release`'s `docc` job (20 → 45, T010), each because a new step
  bound changed its arithmetic.
