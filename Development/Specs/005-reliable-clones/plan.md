---
feature: 005
title: Authenticate github.com clones and retry fetch flakes in CI
phase: null
status: Planned
updated: 2026-10-11
adrs: []
---

# Authenticate github.com clones and retry fetch flakes in CI

## Summary

GitHub throttles anonymous HTTPS clones on a shared per-IP quota, and every
macOS job in this repository opens with a burst of them — SwiftPM resolving the
root package, `tuist generate` resolving the demo-app workspace, xcodebuild
resolving remote packages. Run 38030982512 (attempt 1, `KernelApp (ios)`)
shows the cost: an anonymous `swift-event` clone timed out, a sibling fetch
crawled for 9.5 minutes, and the dead clone left SwiftPM's shared repository
cache in a state it fataled on (`cannot change to …: No such file or
directory`). This feature authenticates every github.com git request with the
job's own `GITHUB_TOKEN`, closes the poisoned-cache crash path, and wraps the
package-fetch steps in a signature-gated retry — delivered as six small,
independently revertable pull requests. Tooling/CI work, no roadmap phase.
Supersedes the monolithic `RELIABLE-CLONE` approach: same mechanism, none of
the perl.

Requirements and observable behavior: [spec.md](./spec.md). Ordered
implementation work and the PR slicing: [tasks.md](./tasks.md). Evidence —
the throttling diagnosis, the auth mechanism, rejected alternatives including
third-party retry actions and the perl supervisor: [research.md](./research.md).

## Technical Context

**Surface**: GitHub Actions YAML only — two local composite actions under
`.github/actions/` plus wiring in five workflows. No Swift, no product code.
**Mechanism**: `git config --global http.https://github.com/.extraheader` —
the same Authorization header `actions/checkout` sets, applied globally so it
reaches fetchers outside the repo (SwiftPM's clones, xcodebuild's in-process
scm provider). **Token**: the job's ambient `GITHUB_TOKEN` (`contents: read`
in every job that adopts auth; write-scoped jobs are excluded by wiring and
the action warns when it detects one) on a public repo; plaintext in
`~/.gitconfig`, masked in logs, ephemeral runner only. **Bounds**:
`jobs.<id>.steps[*].timeout-minutes` on the calling step plus git's own
`http.lowSpeedLimit`/`lowSpeedTime` — no process supervisor. **Exclusions**:
`docker-builds.yml` — clone *auth* can't reach inside the container where
fetches happen (the cache-disabling flag is a plain CLI arg and does reach
it, so it applies there); the `release` job in
`docc-release.yml` — holds `contents: write` for `gh release upload` and
fetches nothing, so auth would only persist a bigger token; its unused
checkout step is deleted (nothing in the job reads the repo — the checkout's
only effect today is persisting that write token via checkout's
repo-local credential), with
`GH_REPO` added to its env so `gh release upload` resolves the repo without
a checkout.

## Constitution Check

- **Principle I** (Scope & Core alignment): not applicable — no product scope
  change; CI infrastructure only.
- **Principle II** (C++ interop): not applicable — no Swift or C++ touched.
- **Principle III** (Node lifecycle): not applicable.
- **Principle IV** (API surface): not applicable — no public API added.
- **Principle V** (Spec-first & TDD): satisfied — this plan exists before any
  workflow change; both actions get a real test seam via
  `actions-selftest.yml` — an auth smoke case in PR 2 and the retry gate's
  fake-command cases in PR 5, each landing red before its action — while
  workflow *wiring* has no unit-test seam and is covered by T008's
  throwaway-branch run instead.
- **Principle VI** (Cross-platform CI): satisfied — hardens the macOS CI
  matrix against a documented, reproducible failure class; `docker-builds`
  exclusion is documented rather than silently skipped.
- **Principle VII** (Open source): satisfied — no third-party action is added;
  `persist-credentials: false` is required for duplicate-header correctness
  (FR-002; incidentally matches OWASP's baseline — the token's on-disk
  exposure is the same either way, acknowledged not reduced).

## Design

Three independent mechanisms, one per layer of the failure:

1. **Authenticate** — `.github/actions/github-git-auth`: writes the global
   extraheader (masked), sets `http.lowSpeedLimit 1024` / `lowSpeedTime 60`
   (dead transfers self-abort instead of crawling), then a warn-only
   verification per FR-007/FR-008 — workspace-local extraheader count,
   `GIT_TRACE_CURL` send-path probe, and a write-scope check via
   `permissions.push` (GitHub has no token-introspection endpoint; the
   field is the effective-permission proxy). The token is masked in both
   forms per FR-001.
   Pairing per FR-002 and its edge cases:
   `persist-credentials: false` on every checkout and the auth step after
   them — the double-header 400 mechanism lives in spec.md.
2. **Harden** — `--disable-dependency-cache` on *every* `swift`-family step
   that resolves packages (the two `tuist generate` calls, `swift test` /
   `swift run` / `generate-documentation` — the same shared cache, the same
   fatal mid-fetch path — swiftlang/swift-package-manager#9037) and
   `-disablePackageRepositoryCache` on the xcodebuild resolution steps for
   the same belt-and-suspenders (the cache buys nothing on a fresh runner);
   `timeout-minutes: 30` on the generate steps as the pathological
   never-dies bound — the bound covers the whole retry loop, and 30 ≈ the
   per-attempt-10-min × 3 precedent of retry tooling, comfortably over the
   ~21-min worst-legit path (one incident-scale ~10-min crawl plus two
   ~5-min retries and backoffs); and the `tuist-apps` job cap rises 45 → 75
   so the worst-legit generate+build+test path can't be cancelled by the
   job-level ceiling it now fits under.
3. **Retry** — `.github/actions/retry-on-fetch-flake`: a pure-bash loop that
   re-runs the command — bounded by FR-005's three attempts total —
   **only** when the attempt's log matches a
   fetch/transport signature (the set FR-005 owns — including the
   `lowSpeed` aborts layer 1 manufactures) — exits immediately with the real code
   otherwise
   (never masks deterministic failures), backs off linearly, and wipes the
   resolved package's `.build` per FR-006 (`build-dir` input) — so a
   mid-clone corpse can't block the
   retry. No supervisor: macOS has no `timeout`/`gtimeout`, and the bound is
   covered by the step's `timeout-minutes` plus git's `lowSpeed` aborts.

Dropped from `RELIABLE-CLONE`: the ~60-line embedded perl supervisor (its
only load-bearing job — bounding a crawl — is covered declaratively), the
duplicated inline loops (one shared action instead), and nothing else. Kept:
extraheader auth, `persist-credentials: false`, `::add-mask::`, lowSpeed
limits, the git-trace probe, `--disable-dependency-cache`, coverage of every
fetch-performing job across the five macOS workflows.

The pairing rule and the retry routing rule are recorded in
`.github/AGENTS.md` (inside the wiring PRs) — the same home as the repo's
other CI gotchas — not an ADR: they are workflow-hygiene constraints, not
architecture.

## Verification

- [ ] `git ls-remote` trace in a job log shows `Send header: Authorization`
      on github.com requests after the auth step (SC-001)
- [ ] Probe and count behave per FR-007 (workspace-local, `--includes`
      catches checkout v6's separate credential file) (SC-001)
- [ ] The write-scope check behaves per FR-008 — verified once against a
      throwaway job temporarily granted `contents: write` (SC-001)
- [ ] An attempt failing with a fetch signature is retried and a later
      attempt leaves the step green, per SC-002's evidence (SC-002)
- [ ] A generate step failing on a non-network error exits on attempt 1 with
      the real code (SC-002)
- [ ] Each of the six PRs lands independently: every code-change PR ≤ ~150
      changed lines (PR 1 is prose) and CI green on its own diff (SC-003)

## Risks

- **Token in `~/.gitconfig`** — plaintext, global to the job, no cleanup
  (composite actions cannot register post steps). Acceptable: public repo,
  `contents: read`-scoped in every job that adopts it — enforced by wiring
  scope (the write-scoped `release` job is excluded) plus the action's
  warn-when-write guard — ephemeral GitHub-hosted runner, masked in logs.
  Documented in the action: never reuse on self-hosted runners.
- **`persist-credentials: false` omission** — a new checkout added without it
  in an auth-using job produces two `Authorization` headers → github.com 400.
  Guarded twice: the probe's extraheader-count warning, and the
  `.github/AGENTS.md` pairing rule.
- **Probe false-positive noise** — warn-only by design; a transient probe
  failure costs an annotation, not a job.
- **`--disable-dependency-cache` cost** — refetches into `.build` every job;
  the shared cache was empty on a fresh runner anyway, so the real cost is
  nil.
- **Retry masks nothing but retries everything matching the signature** — a
  signature regex kept deliberately fetch-specific; a deterministic failure
  matching it by coincidence retries twice more and still fails with the real
  code.

## Deferred work

- **Org-wide extraction** — sibling `21-DOT-DEV` repos (swift-tor,
  swift-event, swift-openssl…) run the same anonymous-fetch CI. When a second
  repo adopts, extract both actions to `21-DOT-DEV/actions` consumed via
  `@v1`; the action directories are already self-contained. Not built now —
  release-process overhead for a single consumer.
- **`docker-builds` auth** — would require plumbing the token into the
  container build, a different mechanism; the Linux fetch burst is smaller
  and unobserved failing.
- **Retry on other fetch-invoking steps** (`swift build`, `swift test`,
  `xcodebuild` resolution in apple-builds) — deliberately unwrapped: retrying
  them re-runs build/test work, not just the fetch. Auth + the widened
  cache-hardening is their coverage.
- **Job-level `timeout-minutes` on the jobs that lack one**
  (`apple-builds`, `development-docs`, `docker-builds`, and `docc-release`'s
  `build`/`release` jobs — only its `docc` job carries 20) — a pre-existing
  gap surfaced by this review; `tuist-apps`'s cap is raised here only
  because this feature's step bound changes its arithmetic.

## Division of labor

Solo-maintainer CI work: six sequential pull requests per
[tasks.md](./tasks.md) slicing — each targets `main` after the previous
merges (no stacking needed at this size). End-to-end validation runs on a
throwaway branch before the retry wiring lands.
