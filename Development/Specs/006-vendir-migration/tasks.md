# Tasks — 006 · Migrate Bitcoin Core vendoring from subtree extraction to vendir

Ordered work for [the plan](./plan.md); rationale in
[research.md](./research.md). No `spec.md` — repository tooling with no
user-facing requirements; the parity check in Phase 1 is the red→green
seam (a wrong pattern shows as a diff against the committed tree).

Format: `- [ ] TNNN [P?] what lands · files`. `[P]` marks a task with no
prerequisites. Phase headers close on a **checkpoint** stating what must
be true before the next phase starts. Tick the box in the same change
that lands the task; a checkpoint records measured results as they are
verified (the sibling spec's convention — `*Verified: …*`).

## Phase 0 — Config and recipe

- [x] T001 `vendir.yml`: `git:` checkout entry + 6 source slices + 1
  fixture slice; `ignorePaths` preserve set; license `includePaths`;
  `minimumRequiredVersion: 0.47.0` · `vendir.yml`
- [x] T002 `Scripts/vendor-sync.sh`: fetch → `git apply` all
  `patches/bitcoin/*.patch` → `-d` slice syncs (never a bare sync — it
  re-wipes the patched cache) → memenv + fixture fixups;
  `--locked`-only flag; bash 3.2-safe · `Scripts/vendor-sync.sh`
- [x] T003 `.gitignore`: `.vendir-tmp*`, `.vendir-upstream/` · `.gitignore`

**Checkpoint:** `vendir sync -d .vendir-upstream/bitcoin` fetches the
pinned tag once; config parses under vendir 0.47.0.

## Phase 1 — Byte-parity proof (must precede teardown)

- [x] T004 Run `Scripts/vendor-sync.sh` (first run downloads the
  several-hundred-MB pack) · `vendir.lock.yml` generated
- [x] T005 Diff-verify every destination against HEAD: all six source
  trees byte-identical modulo the six declared license-file
  destinations (five upstream licenses; root `COPYING` lands in both
  `bitcoind` and `libbitcoinkernel`) and
  the one declared `compat.h` delta (upstream's `2009-2024`→
  `2009-present` copyright line, now tracked per the dropped
  exclusion); `Fixtures/` flat with exactly four JSONs; patched files
  equal their committed patched bytes; `include/leveldb/helpers/
  memenv/memenv.h` present and identical to `helpers/memenv/memenv.h` ·
  `git status`, `git diff`, `diff -r`
- [x] T006 Iterate `includePaths`/`excludePaths`/`ignorePaths` until the
  post-recipe tree is clean; record any pattern surprises in
  `vendir.yml` comments · `vendir.yml` — three defects found and fixed:
  bare stage-3 sync re-wiped the patched cache; `ignorePaths`
  directory-globs abort on matched dirs (literal files required); the
  two configure-generated headers needed preserve entries

**Checkpoint:** `git status --porcelain` over the vendored paths shows
the six new license files plus the one-line `compat.h` upstream-drift
modification and nothing else; the lock's SHA equals
`git ls-remote … refs/tags/v31.0^{}`.

## Phase 2 — Teardown

- [ ] T007 Remove the committed mirror (unused Python scripts die with it)
  · `Vendor/` (deleted)
- [ ] T008 Remove the extraction manifest · `subtree.yaml` (deleted)
- [ ] T009 Drop `swift-plugin-subtree` from dev dependencies; update the
  comment naming it; add `exclude:` for the vendored license files in the
  six affected targets · `Package.swift`

**Checkpoint:** `swift package describe` resolves; no manifest errors on
the new `exclude:`s.

## Phase 3 — CI freshness gate

- [ ] T010 `Scripts/vendir-check.sh`: key-allowlist, ref↔lock resolution,
  locked-recipe + clean-status check, local `find` shadow probe over the
  synced checkout, kernel `.cpp` dual-list set-equality (libbitcoinkernel
  `includePaths` ≡ bitcoind `excludePaths`) · `Scripts/vendir-check.sh`
- [ ] T011 `.github/workflows/vendir-check.yml`: `permissions: {}`,
  pinned checkout with `persist-credentials: false`, `github-git-auth`
  before fetch, vendir 0.47.0 pinned by release sha256, path-filtered
  triggers + weekly + dispatch; actionlint/shellcheck clean ·
  `.github/workflows/vendir-check.yml`
- [ ] T012 [P] `.github/AGENTS.md`: workflow inventory row + the
  auth-before-vendir convention · `.github/AGENTS.md`

**Checkpoint:** `Scripts/vendir-check.sh` exits 0 on a clean tree and
fails when a managed file is touched (manual probe); workflow parses.

## Phase 4 — Documentation sweep and governance

- [ ] T013 [P] Root docs: `AGENTS.md` (commands + extraction-flow bullet +
  boundaries + vendored-paths rule), `README.md` (subtree mention) ·
  `AGENTS.md`, `README.md`
- [ ] T014 [P] Patch docs: `patches/README.md` (ignorePaths/wipe model,
  non-patch custom files list), `patches/UPSTREAMING.md` (`git apply
  --check` target `Vendor/bitcoin` → `.vendir-upstream/bitcoin`,
  `subtree.yaml` → `vendir.yml`) · `patches/README.md`,
  `patches/UPSTREAMING.md`
- [ ] T015 [P] `Development/constitution.md`: retarget `subtree.yaml` /
  `swift-plugin-subtree` / `Vendor/bitcoin` naming to the vendir recipe
  (obligations unchanged in substance); amendment-log entry ·
  `Development/constitution.md`
- [ ] T016 [P] `Projects/AGENTS.md` (subtree-sync mentions),
  `.gitattributes` (`Vendor/**` → vendir marks + Fixtures vendored),
  `.jury/policy.toml` (path comments) · `Projects/AGENTS.md`,
  `.gitattributes`, `.jury/policy.toml`
- [ ] T017 `Development/Roadmap/phase-10-vendir-migration.md`: status →
  implemented on completion; correct stale sequencing text in place ·
  `Development/Roadmap/phase-10-vendir-migration.md`
- [ ] T018 Regenerate index tables (`swift run --package-path
  Development/Tools plans`); `swift test --package-path
  Development/Tools`; `vale Development/` if installed ·
  `Development/Specs/README.md`, `Development/ADRs/README.md`

**Checkpoint:** `grep -ri 'subtree\|Vendor/' --exclude-dir=.git` over
docs/workflows/configs finds only historical references (ADRs, amendment
log); tools tests pass.

## Phase 5 — Validation and handoff

- [ ] T019 `swift build` sanity (C/C++ targets unchanged — spot check;
  full matrix stays CI's job) · build
- [ ] T020 Final `git status` review: every change unstaged, nothing newly
  staged, pre-existing staged state untouched · `git status`

**Checkpoint:** maintainer has a clean unstaged change set to review.

## Pull-request slicing

| # | Landed | Pull request | Tasks | Changed lines | Depends on |
|---|---|---|---|---|---|
| 0 | [ ] | Single unstaged change set for maintainer review (per standing instruction, no PRs) | T001–T020 | ~-53 MB / +~1,700 lines | — |

## Deferred

- Gate self-test suite (`Scripts/vendir-check-test.sh` + workflow) — the
  core gate proves stable first (plan, Deferred work).
- GPG verification of the signed tag — vendir's verifier is the frozen
  `x/crypto/openpgp` (carvel-dev/vendir#456 unshipped).
- Updater automation (Renovate-style) — bump stays `ref:` + recipe + PR.
