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
clone timeout, the step retries on its own inside the same job — and the
workspace's remote packages ride inside that fetch, pinned into the
derived-data directory the build steps already read (validation asserts,
rather than assumes, that the failure propagates out of the internal
resolve and into the retry). Jobs whose
build or test commands would otherwise fetch in-step resolve packages in a
dedicated step under the same retry, so the fetching that can still flake is
all fetch-only work. If the
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
   **then** at least the configured wait has elapsed and every
   resolution-state directory the step lists has been removed — covers
   FR-006.
8. **Given** the effective github.com extraheader count inside the workspace
   (`--includes`, which sees checkout's separate credential file) missing or
   exceeding one — or the probe call itself failing — **when** the auth
   action's verify step runs, **then** a `::warning::` annotation is
   emitted and the job continues — covers FR-007.
9. **Given** a job whose `GITHUB_TOKEN` carries write permission, **when** the
   auth action's verify step runs, **then** a `::warning::` annotation is
   emitted and the job continues — covers FR-008.
10. **Given** a workflow whose `github-git-auth`-using job carries a
    write-capable effective permission — including no `permissions:`
    block declared at either level — a checkout without
    `persist-credentials: false`, a checkout after the auth step, a
    `github-git-auth` step missing its required `token` input, or
    an `AUTH_LINT_EXEMPT` marker outside `actions-selftest.yml`,
    **when** the workflow lint runs at PR time, **then** the lint fails —
    covers FR-009.

## Functional requirements

- **FR-001** Every github.com git request made by a CI job after the auth
  step carries an `Authorization` header built from that job's `GITHUB_TOKEN`.
  - Neither the token nor its base64 form appears unmasked in job logs
    (`::add-mask::` on both before any git read — git's trace redacts the
    header value; `git config` output and step logs do not).
  - every xcodebuild invocation in an auth-using job selects
    `-scmProvider system` — applied uniformly, since any action that
    loads package state can trigger a drift-resolve, and the flag is
    global (even `-version` accepts it); the system git
    reads the config file, while the built-in provider's config
    handling is never relied on.
- **FR-002** No github.com git request in a CI job carries more than one
  `Authorization` header (checkouts in auth-using jobs set
  `persist-credentials: false`).
- **FR-003** Every `swift`-family step in CI that resolves package
  dependencies does so with SwiftPM's shared repository cache disabled
  (`--disable-dependency-cache` — including the Dockerfile's in-container
  `RUN` invocations, which the flag reaches as a plain CLI arg);
  every xcodebuild invocation carries `-disablePackageRepositoryCache`
  for the equivalent effect — including the resolve `tuist generate`
  performs internally, which no workflow flag can reach: the manifest's
  `additionalPackageResolutionArguments` passes it there.
- **FR-004** Every step whose purpose includes resolving package
  dependencies declares an explicit `timeout-minutes` bound — `tuist
  generate` counts: it resolves twice over — and for a step wrapped by
  the retry action the bound covers the whole retry loop.
- **FR-005** A fetch step wrapped by the retry action retries a failed
  attempt — up to three attempts total — only when the attempt's output
  matches a signature from the table below; otherwise it exits immediately
  with the original exit code. The table is authoritative — every row
  carries its selftest case and every selftest printer maps back to a row.

  | Retry — signature on the attempt's log | Selftest case |
  |---|---|
  | `Recv failure: Operation timed out` — the incident-observed text | printer → retried |
  | `Operation too slow` — git's `lowSpeed` abort; the stall-killer manufactures this failure | printer → retried |
  | `Could not resolve host` — transient DNS | printer → retried |
  | `RPC failed; curl (18\|56\|92)` — transport-layer RPC abort | printer → retried |
  | `RPC failed; HTTP 5[0-9][0-9]` — server-side failure | printer → retried |
  | `early EOF` — truncated pack | printer → retried |
  | `unexpected disconnect while reading sideband packet` | printer → retried |
  | `Connection reset by peer` | printer → retried |
  | `Failed to connect` — connect-phase TCP failure/timeout | printer → retried |
  | `The remote end hung up unexpectedly` — server-side abort | printer → retried |
  | `returned error: (50[234]\|429)` — server error or throttle | printer → retried |

  | Do not retry — auth-shaped | Selftest case |
  |---|---|
  | `Authentication failed`; `returned error: 40[13]`; `HTTP 40[13]` | `RPC failed; HTTP 403` printer → exactly one attempt |

  - Exclusion is checked before inclusion — a log matching both (`RPC
    failed; HTTP 403` carries a transport signature AND a 4xx) fails
    immediately: a dead credential must never burn three attempts. `RPC
    failed` is never a bare signature — unqualified it also matches auth
    rejections, the exact failures meant to fail fast; it is always
    written transport-scoped (`curl 18|56|92` or `HTTP 5xx`). T008's
    canary isn't wrapped at all, so its single attempt comes from the
    job shape, not the exclusion.
  - `Could not resolve host` retries a mistyped manifest host twice more
    before failing with the real code — the accepted cost of matching
    DNS failures at all, recorded here rather than discovered in a run.
  - "Original exit code" means the code observed at the step boundary —
    for a wrapped `swift package … tuist` step that is SwiftPM's generic
    failure code: the plugin reports tuist's failure as a diagnostic
    rather than propagating its exit value (confirmed in the vendored
    plugin source), so T008 asserts nonzero,
    never a tuist-specific code.
- **FR-006** Before each retry, the action waits the configured backoff and
  removes every directory the wrapped step's package resolution writes into,
  so a fetch corpse cannot survive into the next attempt. The directories
  arrive as a `cleanup-dirs` input — one path per line, defaulting to
  `.build`; relative paths resolve against the workspace; entries may
  carry workflow expressions (`${{ … }}`) — the runner expands them
  before the action ever sees the text — and are deleted as the expanded
  paths.
  - **FR-006a — input reading.** Entries are read line-by-line
    (`IFS= read -r` looped on `|| [[ -n $line ]]` so a final unterminated
    line is not silently dropped — a `|-` block scalar strips it) with
    no word-splitting and no glob expansion: taken literally, `~`,
    `$HOME`, `$VAR`, `*` are never expanded, so a stray one lands
    inside the workspace and warns as absent.
  - **FR-006b — safety guard.** Every entry is checked before deletion:
    it must normalize to an absolute path strictly inside
    `$GITHUB_WORKSPACE` or `$RUNNER_TEMP` — existing entries resolved
    through symlinks (`realpath`-style); for a missing entry the
    deepest *existing* ancestor resolves through symlinks and only the
    non-existent tail is lexical — otherwise `link/newdir` with `link`
    a symlink to `/etc` would pass the text check while `rm -rf`
    follows the intermediate link out — and the two roots are
    canonicalized the same way before the comparison. The roots
    themselves and anything outside either tree warn and are skipped
    rather than `rm -rf`'d, so `/` or `../..` cannot reach outside the
    job's trees.
  - **FR-006c — visibility.** An entry that names nothing emits
    `::warning::` — a silently skipped path would quietly disable
    half the wipe.
  - **FR-006d — per-step entries.** A wrapped `swift package` step
    lists the resolved manifest's `.build` — for `swift package …
    -p Projects/` calls that is the repo **root** `.build` (`-p` is
    Tuist's arg, not SwiftPM's `--package-path`). A wrapped
    `xcodebuild` step lists its `-clonedSourcePackagesDirPath`-pinned
    dir, the entry carrying the same expression the pin flag does.
    A wrapped `tuist generate` step lists root `.build` plus
    `${{ env.DERIVED_DATA }}/SourcePackages` — the two resolves it
    performs and the CI-only manifest pin behind them are
    research.md's §6; pinned, the remote graph fetches once inside
    the retried step and the builds' `-derivedDataPath .derivedData`
    reads it warm.
- **FR-007** The auth action emits a `::warning::` annotation — without
  failing the job — when the probe call itself fails, or when the
  traced `ls-remote` fails to send exactly one `Authorization` header
  per request — counted as case-insensitive `=> Send header:
  authorization:` lines versus `=> Send header: (GET|POST) ` request
  lines, where equal-at-zero is inconclusive (a probe that died before
  sending proves nothing; the request count must be ≥ 1) — or when the
  effective github.com extraheader count differs from one — count and
  probe both run inside the workspace, where repo-local config applies
  to the traced request.
- **FR-008** The auth action emits a `::warning::` annotation — without
  failing the job — when the job's `GITHUB_TOKEN` reports write access to
  the repository (`permissions.push`), because only `contents: read` jobs
  are meant to adopt it; an absent field or a failed API call is
  inconclusive — a `::notice::`, never a misleading warning.
- **FR-009** A static workflow lint — run by the ubuntu-only
  `workflow-lint` workflow (triggered on `.github/workflows/**`,
  `.github/actions/**`, `.github/actionlint.yaml`, and
  `.github/scripts/**`) at PR time —
  fails when a job that uses `github-git-auth` carries a
  write-capable effective permission (the job's `permissions:` block if
  present, otherwise the workflow's; any write value or `write-all`
  counts — and no block declared at either level fails too, since the
  token then inherits the repo default, which may be write), a
  checkout without `persist-credentials: false`, a
  checkout ordered after the auth step, or a `github-git-auth` step
  missing its required `token` input — the mechanical form of
  FR-008's scope rule and FR-002's ordering rule, checked
  deterministically at PR time; FR-008's runtime warn-guard stays as
  backup for what static parsing cannot see. The `token` rule covers
  the hole `.github/actionlint.yaml` documents: actionlint ≤1.7.12
  can't parse `uses: $/…`, so its input validation never sees those
  steps. One exemption exists: a
  job may declare `AUTH_LINT_EXEMPT: "<reason>"`, which exempts ONLY
  the write-permission rule — the checkout checks still apply — and
  the marker itself fails the lint in any file other than
  `actions-selftest.yml`, the only place a deliberately write-scoped
  job belongs (its FR-008 canary).

## Measurable outcomes

- **SC-001** In a job log, the auth step's verify output confirms an
  `Authorization` header on every github.com request in the trace
  (header lines == request lines, ≥ 1) and reports
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
- **SC-003** The feature lands as the pull requests in the slicing
  table — prose-only amendment PRs excluded — each independently
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
  authenticate at a tag ref checked out via an explicit `ref:`
  (`release_tag` on manual re-runs), which can differ from the commit the
  workflow file came from: `./` resolves a local action from the
  *checked-out* tree and dies `Can't find action.yml` on tags cut before
  the action existed, so both jobs use `uses: $/…` instead — the
  self-repository reference resolves at the workflow's own running commit
  (runner ≥2.336.0; GitHub-hosted `macos-26` qualifies). The `release`
  job is excluded: it fetches nothing and its token is
  `contents: write`, so its unused checkout step is removed (the
  checkout's only effect was persisting that token in checkout's
  repo-local credential — nothing in the job reads repo files) and
  `GH_REPO` is set so `gh release upload` resolves the repo without
  one.
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
- **A `cleanup-dirs` entry that names nothing or escapes the job's
  trees** — warned on and skipped; the annotation, not silence, is what
  lets a wiring mistake like a stray `~` or `..` surface in the
  throwaway run rather than inside a real retry.
- **The repo-root `Tuist.swift` pin stops applying** (version drift, a
  silently ignored option, or the `TUIST_` variable unset in a workflow) —
  generate's fetch returns to the default DerivedData, the builds
  re-clone, and the post-generate invariant check warns on *every* run —
  green ones included — while the pinned `.derivedData/SourcePackages`
  entry still warns on each retry and downstream logs show `Fetching`
  lines: the regression announces itself rather than hiding an unwiped
  corpse or an unretried fetch.
- **In-process xcodebuild fetches** — covered by explicit `-scmProvider
  system` on every resolving invocation and in the manifest's
  internal-resolve args: the system git reads the config FILE, an
  env-var-only injection would miss, and no default-provider assumption is
  relied on — the throwaway canary (a deliberately wrong header that must
  break a re-run generate's internal resolve) proves the whole chain
  obeys it.

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
  load-bearing control regardless. Two gits exist on the runner: that
  2.55 is the PATH git the probe and SwiftPM's clones invoke, while
  `-scmProvider system` has xcodebuild call the git it resolves — both
  read `~/.gitconfig` through the URL-scoped key, and the canary covers
  the xcodebuild side.
- `actions/checkout` semantics as shipped (v6): `persist-credentials`
  defaults to `true`.
- SwiftPM supports `--disable-dependency-cache` (verified on the current
  toolchain).
