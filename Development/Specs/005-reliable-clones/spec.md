# Spec — 005 · Authenticate github.com clones and retry fetch flakes in CI

Feature 005 · Status lives in [plan.md](./plan.md) · Design rationale in
[research.md](./research.md) · Ordered work in [tasks.md](./tasks.md)

## Summary

Every CI job that fetches Swift packages sends each github.com git request
with the job's `GITHUB_TOKEN`, so the fetches leave GitHub's anonymous-clone
throttle quota. Package-fetch steps also stop using SwiftPM's shared
repository cache (whose mid-death crash is unrecoverable in-step), gain an
explicit step timeout, and retry automatically — only when the failure looks
like a network flake, never when it looks like a real error.

## User journey

A maintainer pushes to `main`. Each macOS job that resolves packages checks
out with `persist-credentials: false`, runs `github-git-auth` (configures the
global git header, prints one line confirming git sends `Authorization`), then
fetches packages — authenticated, off the anonymous quota. If `tuist generate` hits a
clone timeout, the step retries on its own inside the same job. If the
manifest is actually broken, the step fails immediately with the real error —
no retries, no masking.

**Independent test:** a throwaway branch exercising the same workflow steps —
the auth probe line appears in the log, a signature-matching failure is
retried and a later attempt leaves the step green per SC-002, and a forced
non-network failure exits on the first attempt.

### Acceptance scenarios

1. **Given** a job that ran the auth step, **when** a git process clones any
   github.com repository (inside or outside the workspace), **then** the
   request carries an `Authorization` header built from the job's
   `GITHUB_TOKEN` — covers FR-001.
2. **Given** a job using the auth action, **when** its checkout step runs,
   **then** the checkout leaves no repo-local github.com credential behind —
   covers FR-002.
3. **Given** a `swift`-family step that resolves packages, **when** SwiftPM
   fetches, **then** clones land under the package's `.build` directory,
   not the shared `~/Library/Caches/org.swift.swiftpm` cache — covers FR-003.
4. **Given** a `tuist generate` step whose fetch never finishes, **when** the
   step's timeout elapses, **then** the step is killed and the job ends —
   covers FR-004.
5. **Given** a fetch step that exits nonzero with a clone-timeout signature
   in its output, **when** the retry action evaluates it, **then** a new
   attempt runs — covers FR-005.
6. **Given** a fetch step that exits nonzero with no fetch signature in its
   output, **when** the retry action evaluates it, **then** the step fails
   immediately with the original exit code — covers FR-005.
7. **Given** a failed fetch attempt, **when** the next attempt starts,
   **then** at least the configured wait has elapsed and the resolved
   manifest's `.build` directory (repo root for these calls) has been
   removed — covers FR-006.
8. **Given** the effective github.com extraheader count inside the workspace
   (`--includes`, which sees checkout's separate credential file) missing or
   exceeding one — or the probe call itself failing — **when** the auth
   action's verify step runs, **then** a `::warning::` annotation is
   emitted and the job continues — covers FR-007.
9. **Given** a job whose `GITHUB_TOKEN` carries write permission, **when** the
   auth action's verify step runs, **then** a `::warning::` annotation is
   emitted and the job continues — covers FR-008.

## Functional requirements

- **FR-001** Every github.com git request made by a CI job after the auth
  step carries an `Authorization` header built from that job's `GITHUB_TOKEN`.
  - Neither the token nor its base64 form appears unmasked in job logs
    (`::add-mask::` on both before any git read — git's trace redacts the
    header value; `git config` output and step logs do not).
- **FR-002** No github.com git request in a CI job carries more than one
  `Authorization` header (checkouts in auth-using jobs set
  `persist-credentials: false`).
- **FR-003** Every `swift`-family step in CI that resolves package
  dependencies does so with SwiftPM's shared repository cache disabled
  (`--disable-dependency-cache` — including the Dockerfile's in-container
  `RUN` invocations, which the flag reaches as a plain CLI arg);
  xcodebuild resolution steps carry `-disablePackageRepositoryCache`
  for the equivalent effect.
- **FR-004** Every `tuist generate` step in CI declares an explicit
  `timeout-minutes` bound.
- **FR-005** A fetch step wrapped by the retry action retries a failed
  attempt — up to three attempts total — only when the attempt's output
  matches a fetch/transport signature; otherwise it exits immediately with
  the original exit code.
  - The signature set includes the incident-observed `Recv failure:
    Operation timed out` and git's `lowSpeed` abort text (`Operation too
    slow`) — without the latter, the stall-killer manufactures failures
    the loop never retries.
- **FR-006** Before each retry, the action waits the configured backoff and
  removes the `.build` of the manifest SwiftPM resolved — for `swift package
  … -p Projects/` calls that is the repo **root** `.build` (`-p` is Tuist's
  arg, not SwiftPM's `--package-path`); the path is a `build-dir` input
  defaulting to `.build`.
- **FR-007** The auth action emits a `::warning::` annotation — without
  failing the job — when git is not observed sending the `Authorization`
  header, when more than one `Authorization` header is sent, when the
  probe call itself fails, or when the effective github.com extraheader
  count differs from one — count and probe both run inside the workspace,
  where repo-local config applies to the traced request.
- **FR-008** The auth action emits a `::warning::` annotation — without
  failing the job — when the job's `GITHUB_TOKEN` reports write access to
  the repository (`permissions.push`), because only `contents: read` jobs
  are meant to adopt it; an absent field or a failed API call is
  inconclusive — a `::notice::`, never a misleading warning.

## Measurable outcomes

- **SC-001** In a job log, the auth step's verify output confirms
  `Send header: Authorization` on a real github.com request and reports
  exactly one configured extraheader; a missing/broken config or a
  write-scoped job token produces a warning annotation, never a step
  failure.
- **SC-002** In the permanent retry selftest (the counter-file case
  described in T006): an attempt failing with a fetch signature is
  retried and a later attempt's exit 0 leaves the step green; a step
  failing on a non-network error exits on attempt 1 with its real code.
  A real forced timeout can't produce the first arm — `lowSpeed` is
  global and would abort every attempt — so the counter file
  manufactures the single signature-printing failure.
- **SC-003** The feature lands as six pull requests, each independently
  mergeable with CI green on its own diff; every code-change PR is ≤ ~150
  changed lines (PR 1 is prose).

## Edge cases

- **Repo flips private** — the `GITHUB_TOKEN` clone auth keeps working
  (`contents: read` covers it); nothing in the design assumes a public repo
  except the residual-risk assessment.
- **Self-hosted runner** — documented do-not-use inside the action: the token
  would persist in a shared `~/.gitconfig` across jobs and parallel jobs
  would fight over it.
- **Tagged-release checkout** (`docc-release`) — the `build`/`docc` jobs
  authenticate identically at a tag ref; the `release` job is excluded: it
  fetches nothing and its token is `contents: write`, so its unused checkout
  step is removed (the checkout's only effect was persisting that token in
  checkout's repo-local credential — nothing in the job reads repo files)
  and `GH_REPO` is set
  so `gh release upload` resolves the repo without one.
- **A write-scoped job wired to auth by mistake** — the action warns
  (`::warning::`) and continues; exclusion is by wiring, the
  `permissions.push` check is the tripwire for drift.
- **A second checkout or step adds another extraheader** — two
  `Authorization` headers make github.com answer a bare 400; checkout v6
  stores its credential in a separate repo-local file, so the count runs
  inside the workspace with `--includes`, and the probe also warns when the
  trace shows more than one `Authorization` line or the `ls-remote` call
  fails outright.
- **A checkout placed *after* the auth step in the same job** — the
  checkout's own fetch carries both headers and fails with a 400 outright,
  not a warning: the pairing rule requires auth to *follow* every checkout
  in the job, not merely coexist with it.
- **The `permissions.push` check can't determine the scope** — the field may
  be absent for installation tokens, and the API call itself can fail on a
  flaky network; either produces an inconclusive `::notice::`, never a
  warning and never a failure.
- **`docker-builds` fetches inside the container** — runner-level global
  git configuration cannot reach in-container clones, so the workflow is
  outside the auth layer's scope; `--disable-dependency-cache` still
  applies there as a plain CLI arg. Runner auth for Docker is deferred.
- **A stall converted to failure by `lowSpeed`** — the abort text is part of
  the retry signature, so the failure is retried, not terminal.
- **A retry attempt fails on a different signature-free error** — the step
  exits immediately; retries never mask a new failure mode.
- **Fetch succeeds on a later attempt** — the step proceeds normally; the
  attempt count is visible in the grouped log.
- **In-process xcodebuild fetches** — covered because the config lives in the
  git config FILE; an env-var-only injection would miss them (verified in
  research.md §2).

## Assumptions and dependencies

- Anonymous-clone throttling is the incident mechanism (cli/cli#14329; the
  run's 569-second fetch and `Recv failure` on anonymous clones).
- GitHub-hosted ephemeral macOS runners; no reliance on `timeout`,
  `gtimeout`, or perl being present.
- Public repository; jobs that adopt auth grant `contents: read` — the
  token's blast radius if exposed stays small, write-scoped jobs are kept
  out of the wiring, and the warn-guard flags one wired in by mistake.
- git ≥ 2.34 on runners (HTTP/2 header-redaction fix in `GIT_TRACE_CURL`);
  the `macos-26` image README lists 2.55.0 — the fix is years old so any
  current image (`macos-26`, `xcode-27`) clears it, and masking is the
  load-bearing control regardless.
- `actions/checkout` semantics as shipped (v6): `persist-credentials`
  defaults to `true`.
- SwiftPM supports `--disable-dependency-cache` (verified on the current
  toolchain).
