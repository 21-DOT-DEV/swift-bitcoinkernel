# Tasks — 006 · Migrate Bitcoin Core vendoring from subtree extraction to vendir

Ordered work for [the plan](./plan.md); rationale in
[research.md](./research.md). No `spec.md` — repository tooling with no
user-facing requirements; the parity check is the red→green seam (a wrong
pattern shows as a diff against the committed tree).

Format: `- [ ] TNNN [P?] what lands · files`. `[P]` marks a task with no
prerequisites. Phase headers close on a **checkpoint** stating what must be
true before the next phase starts. Tick the box in the same change that lands
the task; a checkpoint records measured results as they are verified.

## Phase 0 — Config and recipe (landed)

- [x] T001 `vendir.yml`: `git:` checkout entry + 6 source slices + 1
  fixture slice; `ignorePaths` preserve set; license `includePaths`;
  `minimumRequiredVersion: 0.47.0` · `vendir.yml`
- [x] T002 First sync command: `Scripts/vendor-sync.sh` (fetch → patch the
  checkout → copy → two fixups) · `Scripts/vendor-sync.sh`
- [x] T003 `.gitignore`: `.vendir-tmp*`, `.vendir-upstream/` · `.gitignore`

**Checkpoint:** one sync fetched the pinned tag once and filled every
destination; the config parsed under vendir 0.47.0.

## Phase 1 — Byte-parity proof (landed)

- [x] T004 Run the sync · `vendir.lock.yml` generated
- [x] T005 Diff-verify every destination against the committed tree ·
  `git status`, `git diff`, `diff -r`
- [x] T006 Iterate `includePaths`/`excludePaths`/`ignorePaths` until the
  post-sync tree is clean · `vendir.yml`

**Checkpoint:** the vendored destinations reproduced byte for byte, modulo
the declared license additions and upstream drift recorded in the phase's PR;
the lock's SHA equaled the peeled `v31.0` tag.

## Phase 2 — Teardown (landed)

- [x] T007 Remove the committed mirror · `Vendor/` (deleted)
- [x] T008 Remove the extraction manifest · `subtree.yaml` (deleted)
- [x] T009 Drop `swift-plugin-subtree` and exclude vendored license files ·
  `Package.swift`

**Checkpoint:** `swift package describe` resolves; the committed mirror,
manifest, and plugin are gone.

## Phase 3 — Design realignment (PR 1)

- [x] T010 Correct the plan, research, and task list in place for the
  two-command end state and the seven-PR delivery shape ·
  `Development/Specs/006-vendir-migration/{plan,research,tasks}.md`
- [x] T011 Record the durable decisions: ADR 0012 written, ADR 0010 marked
  superseded, and ADR 0011 given a dated correction; regenerate the indexes ·
  `Development/ADRs/0012-vendor-sync-is-two-plain-commands.md`,
  `Development/ADRs/0010-vendir-replaces-subtree-mirror.md`,
  `Development/ADRs/0011-single-fetch-upstream-checkout.md`,
  `Development/{Specs,ADRs}/README.md`

**Checkpoint:** `swift run --package-path Development/Tools plans --check`,
the Development tools tests, and Vale are green; no operational file changes.

## Phase 4 — Header-copy cleanup (PR 2)

- [ ] T012 Replace the two hand-copied upstream headers with forwarding
  headers, delete the three unused duplicated build-setting headers, and make
  the transitional `vendir.yml`/`Scripts/vendor-sync.sh` preservation rules
  match that layout ·
  `Sources/libbitcoinkernel/include/bitcoinkernel.h`,
  `Sources/leveldb/include/leveldb/helpers/memenv/memenv.h`,
  `Sources/bitcoind/include/`, `vendir.yml`, `Scripts/vendor-sync.sh`,
  `.gitattributes`
- [ ] T013 Validate the slice with `swift build --build-tests` and the
  non-embedded package tests in default and `wallet` configurations · build

**Checkpoint:** the old pre-copy-patch sync still works, the forwarding
headers compile, and no deleted header is read by the build.

## Phase 5 — Fixture layout cleanup (PR 3)

- [ ] T014 Sync the three used JSON fixtures into `Fixtures/rpc/` and
  `Fixtures/blockfilters/`, update the three test lookups, delete unused
  `rpc_psbt.json`, and remove the flattening fixup from the transitional
  script · `vendir.yml`, `Scripts/vendor-sync.sh`,
  `Tests/BitcoinTests/Fixtures/`,
  `Tests/BitcoinTests/Models/{BlockchainModelTests,RawTxPSBTUtilModelTests}.swift`
- [ ] T015 Validate the affected fixture tests plus the non-embedded package
  suite · tests

**Checkpoint:** the old pre-copy-patch sync still works and the test bundle
finds every synced fixture in its new location.

## Phase 6 — Byte-preserving `vendir.yml` rewrite (PR 4)

- [ ] T016 Rewrite the recipe so the download is filtered at fetch time,
  library entries copy from their own upstream subfolders, brace patterns
  replace expanded globs, wholly hand-written folders use file-only
  `ignorePaths` globs, and the lock is regenerated · `vendir.yml`,
  `vendir.lock.yml`, `.gitignore`
- [ ] T017 Prove the rewrite is byte-preserving by replaying the transitional
  sync and requiring no difference in the committed vendored tree ·
  `git status --porcelain`

**Checkpoint:** the copied tree is unchanged; only the recipe becomes simpler
and nearer its final shape.

## Phase 7 — Patch relocation and script retirement (PR 5)

- [ ] T018 Rewrite the five patches to this repository's `Sources/...` paths
  and delete `Scripts/vendor-sync.sh` · `patches/bitcoin/*.patch`,
  `Scripts/vendor-sync.sh` (deleted)
- [ ] T019 Update every operational document that would otherwise still name
  the script: the `vendir.yml` header, root `AGENTS.md`, `SECURITY.md`,
  `patches/README.md`, `patches/UPSTREAMING.md`, and
  `Development/constitution.md` · those files
- [ ] T020 Validate `vendir sync --locked && git apply
  patches/bitcoin/*.patch && git status --porcelain`, then run the
  non-embedded package suite in default and `wallet` configurations · sync,
  build

**Checkpoint:** the two plain commands reproduce the committed tree, no
documented sync command names the deleted script, and the package still
builds and tests.

## Phase 8 — CI freshness check (PR 6)

- [ ] T021 Add `.github/workflows/vendir-check.yml`: least-privilege
  permissions, checkout without persisted credentials, `github-git-auth`,
  vendir 0.47.0 pinned by SHA-256, locked sync through
  `retry-on-fetch-flake`, patch application, and an empty
  `git status --porcelain` requirement · `.github/workflows/vendir-check.yml`
- [ ] T022 Document the workflow in `.github/AGENTS.md` and validate the
  workflow locally with actionlint · `.github/AGENTS.md`
- [ ] T023 Confirm the workflow passes on a real GitHub runner · CI

**Checkpoint:** the CI job reproduces the committed tree with no difference;
no branch-protection or required-check change is made.

## Phase 9 — Closeout (PR 7)

- [ ] T024 Finish the explanatory documentation sweep: remaining patch
  memos, project documentation, and any stale sync references not required
  in PR 5 · documentation
- [ ] T025 Update the roadmap and Spec 006 status when implementation is
  merged, regenerate the index tables, and keep the Development tools tests
  and Vale green · `Development/Roadmap/phase-10-vendir-migration.md`,
  `Development/Specs/README.md`, `Development/ADRs/README.md`
- [ ] T026 Final maintainer review of the landed series and its CI evidence ·
  `git status`, CI

**Checkpoint:** Spec 006 can move to `Implemented`; no migration validation
box remains unchecked except work explicitly deferred.

## Pull-request slicing

| # | Landed | Pull request | Tasks | Changed lines | Depends on |
|---|---|---|---|---|---|
| 1 | [ ] | Design realignment and decision records | T010, T011 | ~1,400 prose | — |
| 2 | [ ] | Header-copy cleanup | T012, T013 | ~1,850, deletion-dominated | PR 1 |
| 3 | [ ] | Fixture layout cleanup | T014, T015 | ~300, deletion-dominated | PR 2 |
| 4 | [ ] | Byte-preserving `vendir.yml` rewrite | T016, T017 | ~280 | PR 3 |
| 5 | [ ] | Patch relocation and script retirement | T018–T020 | ~250 | PR 4 |
| 6 | [ ] | CI freshness check | T021–T023 | ~120 | PR 5 |
| 7 | [ ] | Closeout | T024–T026 | ~100 | PR 6 |

Numbered order is the landing sequence. The PRs are strictly sequential and
all target `main`: existing workflows do not test pull requests targeted at
intermediate stack branches. Phases 0–2 already landed through the first two
migration PRs and are outside this table.

## Deferred

- GPG verification of the signed tag — vendir's verifier is the frozen
  `x/crypto/openpgp` (carvel-dev/vendir#456 unshipped).
- Updater automation — a bump stays `ref:` + sync + PR.
