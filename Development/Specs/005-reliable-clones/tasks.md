# Tasks — 005 · Authenticate github.com clones and retry fetch flakes in CI

Ordered work for [the plan](./plan.md); requirements cited as `FR-NNN` from
[spec.md](./spec.md); rationale in [research.md](./research.md).

## Phase 0 — The plan itself

- [ ] T001 This spec and the regenerated specs index ·
  `Development/Specs/005-reliable-clones/{plan,spec,tasks,research}.md`,
  `Development/Specs/README.md`

**Checkpoint:** `swift run --package-path Development/Tools plans --check`
is green; the index lists feature 005.

## Phase 1 — The auth mechanism, inert

- [ ] T002 `github-git-auth` composite action: global
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
  `--includes` count of 1 and `Send header: Authorization` in a trace.
  A second job granted `contents: write` asserts the FR-008 warning
  fires — gated on `head.repo.full_name == github.repository` so it
  runs only where the grant can take effect (fork tokens stay
  read-only regardless of the block, and an unconditional job would
  red every fork PR). Its own
  checkout follows the FR-002 pairing it exercises. Also runs
  `actionlint` + `shellcheck` (brew-installed binaries — the repo's
  existing `brew install vale` precedent — not third-party actions; if a
  newer lint rule ever fails an unrelated diff, pin the versions then)
  over the workflows and action files so quoting/`errexit`
  mistakes in inline bash are linted, not learned by live failure.
  Workflow-level `permissions: {}` + job `contents: read` per the repo's
  least-privilege convention.
  `.github/actionlint.yaml` declares `xcode-27` (a custom label
  actionlint's built-in list doesn't know — verified: `runner-label`
  errors on `flake-hunt:45` and the four `tuist-apps` matrix rows), and
  two pre-existing findings are fixed so the gate is green: drop the
  always-empty `${{ matrix.suffix }}` from `tuist-apps:13` (renders
  identical names) and resolve `docc-release:162`'s SC2012 (fixed known
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

**Checkpoint:** no production workflow calls the action yet — only
`actions-selftest.yml` exercises it; fetch paths are unchanged.

## Phase 2 — Turn auth on everywhere packages are fetched

- [ ] T003 Add `persist-credentials: false` to every checkout and the
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
  exceptions. Same edit
  tightens the "private repos" framing in the least-privilege bullet and the
  `permissions: {}` gotcha — the rule is least-privilege generally, the repo
  is public · `.github/AGENTS.md`

**Checkpoint:** every fetch-performing macOS job's log shows the "github.com
git requests carry the Authorization header" line after checkout.

## Phase 3 — Close the fatal cache path and bound the fetch

- [ ] T005 Add `--disable-dependency-cache` to every `swift`-family step
  that resolves packages (the `tuist generate` calls, `swift test`/`run`,
  `generate-documentation`, and the Dockerfile `RUN` lines — the flag is a
  plain CLI arg that reaches in-container where clone auth cannot),
  `-disablePackageRepositoryCache` to the xcodebuild resolution steps,
  `timeout-minutes: 30` to the generate steps,
  and raise the `tuist-apps` job cap 45 → 75 so the worst-legit retry path
  fits under it (FR-003, FR-004) ·
  `.github/workflows/{apple-builds,development-docs,docc-release,flake-hunt,
  tuist-apps}.yml`, `Dockerfile`

**Checkpoint:** a `tuist generate` log shows clones writing under
`.build/repositories`, not `~/Library/Caches/org.swift.swiftpm`.

## Phase 4 — The retry mechanism, inert

- [ ] T006 `retry-on-fetch-flake` composite action: bash loop gated on a
  fetch/transport signature regex (the set FR-005 owns: incident text plus
  the `lowSpeed` aborts layer 1 manufactures) —
  and each attempt runs under `if ! cmd 2>&1 | tee log` (composite
  `shell: bash` steps carry `-e -o pipefail`; a bare `cmd` would end the
  step before the signature check or any retry can run) —
  ≤3 attempts, linear backoff, the resolved package's `.build` wiped
  between attempts per FR-006 (`build-dir` input, default `.build`) —
  real exit code on non-signature failures — PR 5 also extends the
  selftest with fake-command cases: `Recv failure` printer → three
  attempts, `Operation too slow` printer → a retry, silent exit-3 → one
  attempt code 3, and a counter-file case — attempt 1 prints `Recv
  failure` + exits 1, attempt 2 exits 0 → exactly two attempts and the
  step green, the permanent SC-002 retry-then-success evidence (a real
  forced timeout can't demonstrate it: `lowSpeed` is global and would
  abort every attempt; the counter and the per-attempt log live in
  `$RUNNER_TEMP` — inside `build-dir`, FR-006's wipe would reset them
  and the case could never pass) — so the signature set FR-005 owns gets a permanent
  regression check on every future edit — pure
  bash, no supervisor (FR-005, FR-006) ·
  `.github/actions/retry-on-fetch-flake/action.yml`

**Checkpoint:** no production workflow calls the action yet — the
selftest's retry cases exercise it; fetch paths unchanged.

## Phase 5 — Turn the retry on for the fetch steps

- [ ] T007 Wrap the `tuist generate` steps in `retry-on-fetch-flake`
  (label + command inputs; the step keeps its `timeout-minutes` as the outer
  bound); record the routing rule — fetch steps retry through the shared
  action, new signatures land there *with a selftest case* (the routing
  rule's maintenance half — a signature added without a case recreates
  the untested-logic gap) (FR-005, FR-006) ·
  `.github/workflows/{tuist-apps,flake-hunt}.yml`, `.github/AGENTS.md`

**Checkpoint:** `Generate workspace` steps invoke the action; logs show the
attempt group format.

## Phase 6 — End-to-end validation on a throwaway branch

- [ ] T008 Push a throwaway branch carrying the end state and observe: the
  auth step's log shows `***` wherever token material would print (FR-001's
  masking half); the
  probe confirms `Send header: Authorization` with exactly one effective
  extraheader counted with `--includes` (verifies FR-001, FR-002, FR-007);
  the `permissions.push` warn-guard reads the job's token scope correctly —
  including whether the field is even present for a `GITHUB_TOKEN`, checked
  against a throwaway job temporarily granted `contents: write` (verifies
  FR-008); `swift test`/`generate-documentation`/xcodebuild accept their
  cache-disabling flags (verifies FR-003 mechanically); the generate log
  shows `.build`-local clones (verifies FR-003); retry-then-success
  demonstrated by the counter-file case (attempt 1 signature-fails,
  attempt 2 exits 0 → two attempts, step green) while a forced
  non-network failure exits on attempt 1
  (verifies FR-005, FR-006); a checkout deliberately placed after the auth
  step fails its own fetch with the predicted 400 — proves the ordering
  rule (verifies FR-002's premise); a step forced into git's `lowSpeed` abort
  (absurd `lowSpeedLimit`, tiny `lowSpeedTime`, set repo-locally — a
  `--global` set would leak into later steps' fetches) is retried — the signature
  catches the failure mode layer 1 manufactures; a `timeout-minutes: 1`
  test step is killed at
  the bound (verifies FR-004); and the wipe targets the `.build` that
  actually exists (repo root, not `Projects/`), its presence checked before
  deletion (verifies FR-006's premise) ·
  throwaway branch, deleted after

**Checkpoint:** every verification box in plan.md ticked from observed runs.

## Pull-request slicing

| # | Landed | Pull request | Tasks | Changed lines | Depends on |
|---|---|---|---|---|---|
| 1 | [ ] | The plan documents | T001 | ~400 prose | — |
| 2 | [ ] | `github-git-auth` action, inert + `actions-selftest` workflow + `actionlint.yaml` + pre-existing lint fixes | T002, T009 | ~125 | — |
| 3 | [ ] | Auth wired into fetch jobs across five workflows, `release`-job checkout removed, pairing rule | T003, T004 | ~100 | PR 2 |
| 4 | [ ] | Cache flags on all fetch steps + `timeout-minutes: 30` + job-cap bump | T005 | ~55 | — |
| 5 | [ ] | `retry-on-fetch-flake` action, inert + selftest retry cases | T006 | ~100 | PR 2 (selftest workflow) |
| 6 | [ ] | Retry wired into the two generate steps + routing rule | T007 | ~30 | PR 5 |

Numbered order is the recommended landing sequence. PR 4 has no code
dependency and may land in any position; PRs 3, 5 and 6 must follow their
action or workflow PRs. T008 is validation, not a PR — it runs on a throwaway branch before PR 6
merges and the branch is deleted after.

## Deferred

- Extraction to a shared `21-DOT-DEV/actions` repository when a second org
  repo adopts — self-contained directories already; blocked only on a real
  consumer, not design.
- `docker-builds` in-container clone auth — needs token plumbing into the
  image build, a different mechanism.
- Retry wiring for non-dedicated-fetch steps (`swift build`/`test`,
  `xcodebuild` resolution) — retrying them re-runs build/test work, not just
  the fetch; their coverage is auth + the widened cache flags.
- Job-level `timeout-minutes` on uncapped jobs — see plan.md's Deferred
  work item for the authoritative job list; a pre-existing gap — only
  `tuist-apps`'s cap changes here because this feature's step bound
  changed its arithmetic.
