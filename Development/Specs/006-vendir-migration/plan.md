---
feature: 006
title: Migrate Bitcoin Core vendoring from subtree extraction to vendir
phase: 10 · Vendir Migration
status: In Progress
updated: 2026-11-16
adrs: [0010, 0011]
---

# Migrate Bitcoin Core vendoring from subtree extraction to vendir

A tooling migration, not a library change. One `git:` contents entry clones
`bitcoin/bitcoin` at the pinned tag into a gitignored `.vendir-upstream/
bitcoin` checkout, and `directory:` slices copy filtered subsets of it into
the same `Sources/` and `Tests/` destinations the subtree rules populated —
replacing `subtree.yaml`, the `swift-plugin-subtree` dev dependency, and the
committed ~53 MB `Vendor/bitcoin` mirror (1,459 tracked files, ~150 of them
Python scripts nothing extracts). `Scripts/vendor-sync.sh` drives the full
recipe — fetch, `git apply` the five maintained patches onto the pristine
checkout, slice, then two fixups vendir's path rules cannot express — and a
`vendir-check` workflow turns the recipe into a CI freshness gate. Update
automation stays a manual recipe (§Design → Interim updates). Produced
[ADR 0010](../../ADRs/0010-vendir-replaces-subtree-mirror.md) (vendir
replaces subtree + the mirror) and
[ADR 0011](../../ADRs/0011-single-fetch-upstream-checkout.md) (one fetch
feeds all slices). Ordered work: [tasks.md](./tasks.md). Evidence and
measured verification: [research.md](./research.md). No spec.md — repository
tooling with no user-facing requirements; acceptance is byte-parity (§Goal
& success criteria).

## 1. Goal & success criteria

- `Scripts/vendor-sync.sh` reproduces the six extracted trees
  (`Sources/{bitcoind,libbitcoinkernel,crc32c,leveldb,minisketch,
  secp256k1}/`) and `Tests/BitcoinTests/Fixtures/` byte-for-byte against
  git HEAD, modulo exactly the declared deltas — six destination
  license files (five upstream licenses; the root `COPYING` lands in
  both `bitcoind` and `libbitcoinkernel`) plus the one-line
  `compat/compat.h` upstream copyright drift (`2009-2024` →
  `2009-present`, now tracked since its subtree-era exclusion was
  dropped) — the
  project-owned files inside wiped roots ride across via `ignorePaths`,
  and patch-touched files are re-created by `git apply` on every sync.
- Retired and deleted: `Vendor/` (~53 MB tracked, 1,459 files — the unused
  upstream Python/contrib/test tooling dies with it), `subtree.yaml`, and
  the `swift-plugin-subtree` dev dependency. No subtree-specific workflows
  exist here to port.
- Provenance lives in a committed `vendir.lock.yml` — the peeled commit
  SHA `v31.0` resolves to, the record the gate re-checks and an updater
  edits.
- A CI freshness gate keeps the vendored trees honest: the *whole recipe*
  run `--locked` (sync → patches → fixups) must leave a clean
  `git status --porcelain`, and `v31.0`'s remote peel must equal the
  lock's `sha:` — a moved tag or an unsynced `ref:` edit fails by name.
- The five `patches/bitcoin/*.patch` artifacts apply cleanly to the
  pristine checkout on every sync — upstream drift under a patch is a
  loud sync failure, never silent stale bytes.

## 2. Scope

**In scope:** `vendir.yml`, `vendir.lock.yml`, `Scripts/vendor-sync.sh`,
`Scripts/vendir-check.sh`, `.github/workflows/vendir-check.yml`; the
deletions listed above; `Package.swift` (drop the plugin dep;
license-file `exclude:`s on the affected targets); `.gitignore`,
`.gitattributes`, `.jury/policy.toml`; `AGENTS.md`, `README.md`,
`patches/README.md`, `patches/UPSTREAMING.md`,
`Development/constitution.md`, `Projects/AGENTS.md`, `.github/AGENTS.md`,
`Development/Roadmap/phase-10-vendir-migration.md`; this spec and ADRs
0010–0011; regenerated `Development/Specs/README.md` +
`Development/ADRs/README.md` indexes.

**Out of scope (with owners):**

- Upstream content changes — every synced byte is upstream at the pinned
  ref modulo the five declared patch files.
- `Sources/`/`Tests/` layout changes — the extracted trees are
  byte-identical; the two vendir-unexpressible shapes are reproduced by
  fixups, not redesigned.
- The merge ruleset — `vendir-check.yml` reports visibly but joins no
  required set without a maintainer decision (same stance as
  development-docs).
- Updater automation — a bump stays a manual `ref:` edit + recipe + PR;
  the sibling's centralized org updater would consume this repo's
  `vendir.yml` + lock + gate from its own repository when it exists.

## 3. Technical Context

`subtree.yaml` holds 12 extraction rules over one upstream
(`bitcoin/bitcoin @ v31.0`, committed mirror under `Vendor/bitcoin`).
vendir 0.47.0 is installed locally and sets the
`minimumRequiredVersion` floor. The recipe and gate run in bash
(3.2-safe); the gate runs on `ubuntu-slim` with `github-git-auth`
authenticating the ~250 MB fetch (005's throttle research). No product
Swift/C++ is edited — verification is tree parity, not new tests.

## 4. Constitution Check

- **Principle I** (Scope, upstream alignment, local-patches discipline):
  satisfied — same upstream and same release (v31.0), pinned by tag in
  `vendir.yml` and by resolved commit in `vendir.lock.yml`; the patch
  discipline is preserved *mechanically* — `vendor-sync.sh` re-applies
  `patches/bitcoin/*.patch` to a pristine checkout on every sync, so a
  patch that stops applying fails loudly instead of being silently
  preserved. The constitution's `subtree.yaml`/`Vendor/bitcoin` naming is
  updated in place (amendment-log entry) — the obligations are unchanged
  in substance.
- **Principle II** (C++ interop): not applicable — no Swift or vendored
  C/C++ source is edited; the recipe regenerates identical bytes.
- **Principle III** (Node lifecycle): not applicable — no runtime
  behavior changes; the restart-enabling patches carry over
  byte-identical.
- **Principle IV** (API surface): not applicable — no public API change.
- **Principle V** (Spec-first & TDD): satisfied — this plan exists before
  the fetch/teardown executes; the test seam for repository tooling is
  the parity verification itself (recipe output diffed against the
  committed tree — a red state if patterns miss), promoted to CI by
  `vendir-check.sh`, matching how 005 treated workflow wiring.
- **Principle VI** (Cross-platform CI): satisfied — the new gate runs on
  Linux, authenticates the larger fetch through the existing
  `github-git-auth` action per 005, and the Tier 1 matrix is untouched.
- **Principle VII** (Open source): satisfied — the license-preservation
  obligation moves from "files shipped under `Vendor/`" to per-target
  `COPYING`/`LICENSE` files vendored into each tree (matching the
  sibling's treatment); all tooling docs updated.

## 5. Design

**Sync recipe (`Scripts/vendor-sync.sh`).** The maintainer-facing command
is the script, never bare `vendir sync` — the vendored trees are only
correct after all three stages:

1. `vendir sync -d .vendir-upstream/bitcoin` — the sole `git:` entry
   performs the only network fetch (tag `v31.0`, `depth: 1`,
   `skipInitSubmodules` — vendir runs submodule init by default, upstream
   has no `.gitmodules`, and the flag keeps a future one from widening
   the sync). The checkout doubles as the `git apply --check` validation
   tree — the role `Vendor/bitcoin` previously served in
   `patches/UPSTREAMING.md`.
2. `git apply --check` then `git apply` each `patches/bitcoin/*.patch`
   with `--directory=.vendir-upstream/bitcoin`. Whole-patch application —
   no per-file routing — because the checkout mirrors upstream layout;
   `rpc-server-reset.patch` spans two destinations and applies as one
   unit here. A patch that stops applying aborts before any slice copies.
3. `vendir sync -d` for each of the seven slices — *not* a bare sync.
   A bare `vendir sync` re-selects `.vendir-upstream/bitcoin` too,
   re-checking out the pristine ref over the patched tree so unpatched
   bytes land in `Sources/` (observed in the first run: `logging.cpp`,
   `rpc/server.h`, `compat.h` regressed). `-d` selects configured
   directories only; each still gets its full wipe+replace. Then the
   two fixups vendir's path rules cannot express: `cp`
   `helpers/memenv/memenv.h` into
   `include/leveldb/helpers/memenv/` (the synthetic public-header copy —
   upstream ships it only under `helpers/`; `dbwrapper.cpp` includes it
   through `include/`), and flatten the fixtures — vendir forbids
   overlapping contents paths, so the four JSONs arrive repo-relative
   under `Fixtures/{test,src}/` and `mv` up.

**vendir.yml.** Eight `directories:` entries — one `git:` checkout
(listed first; vendir syncs in config order) feeding seven `directory:`
slices — instead of the sibling's canonical one-`git:`-per-destination.
The divergence is fetch arithmetic, justified in
[research.md](./research.md) §2 and ADR 0011: released vendir fetches
once per `git:` contents with no cross-entry cache and fetches every ref
for a named tag, so ~8 entries × bitcoin's ~715-ref pack would download
several hundred MB apiece; one checkout pays it once. `vendir.lock.yml`
is committed (the `git:` cache entry is what keeps real commit-SHA
provenance in it); `.vendir-upstream/` and `.vendir-tmp*` are gitignored.

| Destination | Source shape | `newRootPath` | Notes |
|---|---|---|---|
| `.vendir-upstream/bitcoin` | `git:` — the only fetch | — | `ref: v31.0`, `depth: 1`, `skipInitSubmodules` |
| `Sources/crc32c` | `directory:` slice | `src/crc32c` | `include/`+`src/` `{h,cc}` + `LICENSE` |
| `Sources/leveldb` | `directory:` slice | `src/leveldb` | six `{cc,h}` dirs + `LICENSE` |
| `Sources/minisketch` | `directory:` slice | `src/minisketch` | `include/`+`src/` `{cpp,h}` + `LICENSE` |
| `Sources/secp256k1` | `directory:` slice | `src/secp256k1` | `include/`+`src/` `{c,h}` + `COPYING` |
| `Sources/libbitcoinkernel` | `directory:` slice | — (repo-relative) | `COPYING` + `src/**/*.h` + ~80-entry kernel `.cpp` list |
| `Sources/bitcoind` | `directory:` slice | — (repo-relative) | `COPYING` + remaining `src/**/*.{cpp,c}` + `src/wallet/**/*.h` + `src/ipc/exception.h` |
| `Tests/BitcoinTests/Fixtures` | `directory:` slice | — (nested; fixup flattens) | 4 JSON globs |

**include/exclude translation.** `subtree.yaml`'s `from:`/`exclude:` globs
map to `includePaths`/`excludePaths` (brace groups expanded — the sibling
did the same for greppability). Deliberate deltas, each named in a
`vendir.yml` comment: `**/ipc/**` narrows to `**/ipc/**/*.{cpp,c}` so the
one extracted ipc header (`src/ipc/exception.h`) survives; the
`**/compat/compat.h` exclusion is dropped — the file syncs normally and
`main-function-guard.patch` owns the delta; license files ride
(`COPYING` into the two bitcoin-code targets — `vendir`'s `legalPaths`
default doesn't match that name, so they're explicit `includePaths`;
each library's own `LICENSE`/`COPYING`) with matching `Package.swift`
`exclude:`s. `includePaths` match upstream-repo-relative before
`newRootPath` re-roots — patterns spell `src/<lib>/…` in full (the
sibling verified the same ordering).

**Preserve step.** vendir wipes each `directories[].path` before copying;
`ignorePaths` carries the 21 project-owned files across as literal
entries — modulemaps, `bitcoin-build-{config,info}.h`,
`bitcoin-config.h`, `bitcoind.h`, the `include/` umbrella files, the
`src/bridge/` shims, and the two configure-generated headers
(`crc32c_config.h`, `port_config.h`). Two constraints learned in the
first run: entries must be literal FILE paths — vendir stats each glob
match and aborts on a directory (`include/**` matching `include/config/`
ended the run mid-wipe) — and preservation carries working-tree bytes,
so it cannot resurrect a file already deleted. Patched files are
deliberately absent from
`ignorePaths`: preserving committed patched bytes would freeze them —
the whole point of keeping divergence as `.patch` artifacts is that drift
breaks loudly (research §3). One caveat, same as the sibling's: a *future*
upstream file at an `ignorePaths` destination would be silently shadowed
— the gate's shadow check asserts their absence.

**CI gate.** `vendir-check.yml` — path-filtered on PRs and pushes to
main touching `vendir*.yml`, the eight vendored destinations,
`patches/`, `Scripts/vend{ir,or}-*`, and the workflow itself, plus a
weekly `schedule:` and `workflow_dispatch:` (a moved tag surfaces within
days while the repo sees activity; GitHub disables cron on public repos
after 60 quiet days — best-effort, the PR path is the real gate).
`ubuntu-slim` (git, `yq`, `jq`, coreutils published); `permissions: {}`;
pinned `actions/checkout` with `persist-credentials: false`, then
`github-git-auth` — required here where the sibling ran anonymous: the
fetch is ~250 MB vs. their ~25 MB, and shared-IP throttling is documented
in 005. vendir installed by `curl` plus a hard-coded release SHA-256 in
an `env:` constant (the Vale precedent — a `checksums.txt` from the same
release proves nothing if tampered), pinned at 0.47.0. All check logic
lives in `Scripts/vendir-check.sh` — bash-3.2-safe, named-check argument
per step so each check is a distinct CI failure, a bare run executes all
checks so the gate reproduces locally; exits diff(1)-style — 0 clean,
1 findings (drift dominates: proven mismatch outranks another check's
couldn't-run), 2 nothing found but a check couldn't run — so a network
flake never reads as drift and real drift never hides under one. Config
and lock reads go through `yq 'explode(.)'` — a bare read would print a
YAML alias literally if one is ever introduced. Advisory throughout —
never a required check without a maintainer decision. Five checks, each
a named step, adapted from the sibling's five:

1. **Key allowlist** — every mapping key in `vendir.yml` outside the used
   set fails (vendir drops unknown keys silently — a typo'd
   `excludePath:` syncs green): extended for our schema — `directory:` as
   a contents type (`path` its only key), `newRootPath`, `ignorePaths`,
   `legalPaths`; `git:` limited to `url`/`ref`/`depth`/
   `skipInitSubmodules`. Values pinned: `url:` is the single upstream,
   `directories[].path` in the declared eight-destination set, and
   `directory.path` must be `.vendir-upstream/bitcoin` — a repointed
   source resolves happily through every other check.
2. **Remote resolution** — `git ls-remote <url> refs/tags/v31.0
   refs/tags/v31.0^{}`; the `^{}` line's SHA (the peeled commit — the
   bare ref line is the tag *object* for annotated tags) must equal the
   lock's `sha:`. Runs before the sync: after a tag move the locked SHA
   may be unreachable at `depth: 1`, and a fetch error would mask the
   named failure. The URL argument goes behind `--` and
   `GIT_ALLOW_PROTOCOL=https` covers both the probes and vendir's own
   fetch.
3. **Deterministic tree** — `Scripts/vendor-sync.sh --locked` (the whole
   recipe, not bare `vendir sync` — bare output is deliberately not the
   committed state: unpatched slices, nested fixtures, missing memenv
   copy), then `git status --porcelain --ignored=matching` over the
   vendored paths + `vendir.lock.yml` must be empty.
4. **Shadow check** — for every declared `ignorePaths` entry, translate
   destination-relative → upstream-relative (prepend `newRootPath` where
   the slice re-roots) and `find` the synced checkout for a match: any
   hit means a future upstream file would be silently shadowed. Local
   where the sibling needed `curl` against `raw.githubusercontent.com` —
   our cache is a full checkout, so no network, no 429/retry budget, and
   no anchor-file preflight (the checkout's presence is the anchor).
5. **Dual-list equality** — the kernel `.cpp` literal list appears twice
   in `vendir.yml`: as `Sources/libbitcoinkernel` `includePaths` and as
   `Sources/bitcoind` `excludePaths` (negative polarity by design).
   Assert the two sets are equal — a drifted entry places a translation
   unit in both targets (duplicate symbols) or neither (missing
   symbols), loud at link time but confusing to attribute. Not in the
   sibling's five; ours alone because no vendir construct expresses
   "this list, negated."

Dropped from the sibling's five, with the reason each doesn't apply: the
**same-URL lock-SHA equality** check — vacuous with a single `git:` entry
(theirs cross-compared three secp256k1 pins). Dropped on the sibling's
own re-review and not revived: the **base-SHA comparison** (the
bump recipe's lock-diff read covers the same drift) and the **`gh api`
on-default-branch probe** (bump-time review concern). The **self-test
harness** (`vendir-check-test.sh` + workflow) is deferred — the sibling
landed it last too; the core gate proves stable first.

**Interim updates.** Manual until an org updater exists (sibling ADR
0007): edit `ref:` in `vendir.yml` → `Scripts/vendor-sync.sh` → read the
lock diff — `vendir sync` re-resolves the `git:` entry every run, so a
re-pushed tag rides the bump silently; only the intended SHA should move
— → commit → PR on a `vendor/bitcoin-<ref>` branch with the
`dependencies` label. `minimumRequiredVersion` is a floor, not a pin:
run the version `vendir-check.yml` pins — a newer release could write a
lock format the gate can't check (the sibling warns the same in its
AGENTS recipe).

**Teardown.** After byte-parity is proven: `rm -rf Vendor/` (history
keeps it; the unused Python tooling dies with the mirror), `rm
subtree.yaml`, drop `swift-plugin-subtree` from `Package.swift`, add
license `exclude:`s, sweep stale references (AGENTS.md, README.md,
patches docs, constitution, `Projects/AGENTS.md`, `.github/AGENTS.md`,
`.gitattributes`, `.jury/policy.toml`), update phase-10 status.

## 6. Implementation steps

Ordered as: the config + recipe → the sync reproduced byte-for-byte and
the lock committed → `Vendor/`/`subtree.yaml`/plugin teardown → CI gate
→ docs and governance → validation and handoff. The full task list,
grouped into phases with checkpoints, is in [tasks.md](./tasks.md).

## 7. Verification

- [ ] `Scripts/vendor-sync.sh` reproduces `Sources/{bitcoind,
      libbitcoinkernel,crc32c,leveldb,minisketch,secp256k1}/` and
      `Tests/BitcoinTests/Fixtures/` byte-identical to HEAD, modulo
      exactly the six declared license-file destinations and the
      one-line `compat.h` drift — proven by `git status` and `git diff`
      showing nothing else
- [ ] `vendir.lock.yml` pins the commit `v31.0` peels to (`git ls-remote
      https://github.com/bitcoin/bitcoin refs/tags/v31.0^{}`)
- [ ] Every `patches/bitcoin/*.patch` applies cleanly to the pristine
      checkout (`git apply --check` output in the sync log)
- [ ] `Sources/leveldb/include/leveldb/helpers/memenv/memenv.h` exists
      and matches `helpers/memenv/memenv.h`; `Fixtures/` holds exactly
      the four flat JSONs
- [ ] `Vendor/`, `subtree.yaml`, and the `swift-plugin-subtree`
      dependency are gone; `grep -ri 'subtree\|Vendor/'
      --exclude-dir=.git` over docs, workflows, and configs finds only
      historical/ADR references
- [ ] `Scripts/vendir-check.sh` exits 0 on a clean tree and fails named
      on a touched managed file (manual probe); `vendir-check.yml` is
      actionlint-clean, `permissions: {}`, pinned checkout +
      `persist-credentials: false`, auth-before-fetch
- [ ] `swift build` compiles the C/C++ targets unchanged (spot-check —
      full Tier 1 matrix remains CI's job); `swift test --package-path
      Development/Tools` passes and the `plans` index regenerates
      cleanly
- [ ] `git status` at handoff: all changes unstaged, nothing newly
      staged, pre-existing staged state untouched

## 8. Risks and mitigations

- **Fetch size** — released vendir still fetches all ~715 refs shallowly
  for a named tag (carvel-dev/vendir#453 unshipped at 0.47.0): ~250 MB
  per sync, once per run — acceptable locally; CI authenticates and
  bounds it via `github-git-auth`'s lowSpeed settings so a throttle is a
  bounded failure, not a crawl. A future vendir release with targeted
  fetch shrinks this for free.
- **Tag-object vs commit SHA provenance shift** — `subtree.yaml`'s
  `commit:` recorded the annotated *tag object* SHA; `vendir.lock.yml`
  records the peeled *commit* SHA (same tree). Documented in
  [research.md](./research.md) §6 so a reviewer diffing configs doesn't
  read it as drift — the gate's resolve check compares `^{}` peels for
  the same reason.
- **Shadowed preserve files** — a future upstream file landing at an
  `ignorePaths` destination would be silently preserved over: mitigated
  by the gate's `find`-probe against the synced checkout (none exists
  today — verified at v31.0).
- **Patch rot moves earlier** — by design: a patch that stops applying
  fails the sync instead of silently persisting stale bytes. The recipe
  is the tripwire; the gate replays it `--locked`.
- **`vendir sync -d` and `directory:` semantics drift** — the recipe
  relies on `-d` syncing a single named directory and slices never
  refetching; both pinned by `minimumRequiredVersion` and covered by the
  parity run.
- **Contributors need the vendir binary** — `brew install
  carvel-dev/carvel/vendir`, documented in `AGENTS.md`; CI installs the
  pinned, hash-checked binary — `minimumRequiredVersion` is a floor, so
  a newer local release could write a lock format the gate can't read
  (the AGENTS recipe warns).
- **Gate is advisory** — it reports visibly but joins no required check
  without a maintainer decision; its path filter would also leave a
  required check pending on untouched-path PRs — a required rollout
  needs an always-run path or the filter dropped.
- **Scheduled-run auto-disable** — GitHub stops cron triggers on public
  repos after 60 quiet days, exactly when drift accumulates; the weekly
  run is best-effort detection — the PR-triggered run is the real gate.

## 9. Deferred work

- **Gate self-test suite** — the sibling's `vendir-check-test.sh` +
  dedicated workflow; the core gate proves stable first.
- **GPG verification of the signed `v31.0` tag** — vendir's signature
  verification still runs the frozen `x/crypto/openpgp`
  (carvel-dev/vendir#456 unshipped); a CI-side `git verify-tag` against
  a committed signer keyring is the candidate follow-up — the sibling
  deferred the same way.
- **Updater automation** — a bump stays `ref:` + recipe + PR; the
  sibling's centralized org updater would consume this repo's
  `vendir.yml` + lock + gate from its own repository when it exists.
- **`vendir-check.yml` in the merge ruleset** — maintainer decision; the
  path filter needs an always-run variant first.
- **Scheduled-failure visibility** — a `schedule:` red run notifies only
  the last cron-line editor; an issue-opening follow-up job needs a
  scoped `issues: write` grant on that one job (`permissions: {}` stays).
- **Org-wide extraction of `vendor-sync`/`vendir-check`** — if a second
  21-DOT-DEV repo adopts this cache+slice shape, lift the scripts to a
  shared location; not built for one consumer.

## 10. Division of labor

Solo-maintainer infrastructure work; one reviewable change set, left
unstaged for maintainer review per standing instruction.
