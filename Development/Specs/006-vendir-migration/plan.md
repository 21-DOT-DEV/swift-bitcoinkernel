---
feature: 006
title: Migrate Bitcoin Core vendoring from subtree extraction to vendir
phase: 10 · Vendir Migration
status: In Progress
updated: 2026-11-26
adrs: [0010, 0011, 0012]
---

# Migrate Bitcoin Core vendoring from subtree extraction to vendir

A tooling migration, not a library change. `vendir.yml` pins
`bitcoin/bitcoin` at a release tag. One `git:` entry downloads that tag
into a gitignored `.vendir-upstream/bitcoin` folder, filtered to source
files, and `directory:` entries copy subsets of it into the same
`Sources/` and `Tests/` destinations the subtree rules populated. This
replaces `subtree.yaml`, the `swift-plugin-subtree` dev dependency, and
the committed ~53 MB `Vendor/bitcoin` mirror (2,920 tracked files, 363
of them Python scripts nothing extracts).

The whole sync is two commands with no wrapper script:

```sh
vendir sync && git apply patches/bitcoin/*.patch
```

The same commands with `--locked`, followed by `git status --porcelain`,
verify that the committed files reproduce from the pin, and a
`vendir-check` workflow runs that in CI.

Decisions:
[ADR 0010](../../ADRs/0010-vendir-replaces-subtree-mirror.md) (vendir
replaces subtree and the mirror; superseded by 0012 on how the sync is
driven),
[ADR 0011](../../ADRs/0011-single-fetch-upstream-checkout.md) (one fetch
feeds every copy), and
[ADR 0012](../../ADRs/0012-vendor-sync-is-two-plain-commands.md) (two
plain commands, patches applied to the copied sources). Ordered work:
[tasks.md](./tasks.md). Evidence: [research.md](./research.md). No
spec.md: this is repository tooling with no user-facing requirements,
and acceptance is byte parity (§1).

## 1. Goal & success criteria

- `vendir sync && git apply patches/bitcoin/*.patch` reproduces the six
  extracted trees (`Sources/{bitcoind,libbitcoinkernel,crc32c,leveldb,
  minisketch,secp256k1}/`) and `Tests/BitcoinTests/Fixtures/` byte for
  byte against the committed files.
- Nothing but vendir and git is needed to sync or verify. No script
  encodes ordering, and a bare `vendir sync` is always safe to run.
- Retired and deleted: `Vendor/` (the unused upstream Python, contrib
  and test tooling goes with it), `subtree.yaml`, the
  `swift-plugin-subtree` dev dependency, and `Scripts/vendor-sync.sh`.
- Provenance lives in a committed `vendir.lock.yml`: the commit the
  `v31.0` tag resolved to.
- A CI job keeps the vendored trees honest: the locked sync plus the
  patches must leave `git status --porcelain` empty.
- The five `patches/bitcoin/*.patch` files apply cleanly on every sync.
  Upstream drift under a patch stops `git apply` with an error. It never
  leaves stale bytes silently in place.
- No file in a vendored folder is a hand-kept copy of an upstream file.

## 2. Scope

**In scope:** `vendir.yml`, `vendir.lock.yml`,
`.github/workflows/vendir-check.yml`; the deletions listed above; the
five `.patch` files (paths only); two forwarding headers; the test-data
layout and its three lookups in `Tests/BitcoinTests/Models/`;
`Package.swift` (drop the plugin dependency; license-file `exclude:`s);
`.gitignore`, `.gitattributes`; `AGENTS.md`, `SECURITY.md`,
`patches/README.md`, `patches/UPSTREAMING.md`,
`patches/bitcoin/cmake-ios-library-build.md`,
`Development/constitution.md`, `Projects/README.md`,
`.github/AGENTS.md`,
`Development/Roadmap/phase-10-vendir-migration.md`; this spec and ADRs
0010–0012; the regenerated `Development/Specs/README.md` and
`Development/ADRs/README.md` indexes.

**Out of scope (with owners):**

- Upstream content changes. Every synced byte is upstream at the pinned
  ref, apart from the five declared patches.
- Pruning upstream headers by usage. `src/**/*.h` stays a type-level
  pattern, because which headers a build reads varies by platform.
- The merge ruleset. `vendir-check.yml` reports visibly but joins no
  required set without a maintainer decision.
- Updater automation. A bump stays a manual `ref:` edit, sync, and PR.

## 3. Technical Context

`subtree.yaml` held 12 extraction rules over one upstream
(`bitcoin/bitcoin @ v31.0`, committed mirror under `Vendor/bitcoin`).
vendir 0.47.0 is installed locally, sets the `minimumRequiredVersion`
floor, and is the version CI pins. The CI job runs on `ubuntu-latest`
with `github-git-auth` authenticating the ~250 MB fetch (005's throttle
research). No product Swift or C++ behavior changes. Verification is
tree parity plus the existing build and test matrix.

## 4. Constitution Check

- **Principle I** (Scope, upstream alignment, local-patches discipline):
  satisfied. Same upstream and same release (v31.0), pinned by tag in
  `vendir.yml` and by resolved commit in `vendir.lock.yml`. Patches are
  re-applied on every sync to freshly copied files, so a patch that
  stops applying fails the sync. Constitution 2.4.0 names the two
  commands and adds the reproducibility requirement the CI job enforces.
- **Principle II** (C++ interop): satisfied. No vendored C/C++ source
  changes. The kernel's public C header reaches Swift through a
  forwarding header instead of a duplicate, so the declarations Swift
  imports are the ones the library is compiled from.
- **Principle III** (Node lifecycle): not applicable. The
  restart-enabling patches carry over byte-identical.
- **Principle IV** (API surface): not applicable. No public API change.
- **Principle V** (Spec-first & TDD): satisfied. The test seam for
  repository tooling is the parity check itself, promoted to CI by
  `vendir-check.yml`.
- **Principle VI** (Cross-platform CI): satisfied. The new job runs on
  Linux and authenticates its fetch through the existing
  `github-git-auth` action; the Tier 1 matrix is untouched.
- **Principle VII** (Open source): satisfied. Each upstream license text
  is synced into the folder of the code it covers, with a matching
  `Package.swift` `exclude:`.

## 5. Design

**Sync.** `vendir sync` processes `vendir.yml`'s `directories:` in the
order written. The first entry is the only network fetch: tag `v31.0`,
`depth: 1`, `skipInitSubmodules`, filtered by `includePaths` to C/C++
sources, license texts, three JSON test files, and three build-setting
templates. Every later entry is a `directory:` copy out of that folder.
`git apply patches/bitcoin/*.patch` then applies the five patches
directly onto `Sources/`.

**vendir.yml.** Eight `directories:` entries: the download, six source
trees, and the test data. The shape is ADR 0011's, chosen on fetch
arithmetic ([research.md](./research.md) §2).

| Destination | Copies from (under `.vendir-upstream/bitcoin`) | What |
|---|---|---|
| `.vendir-upstream/bitcoin` | `git:`, the only fetch | `src/**/*.{h,c,cc,cpp}`, license texts, test data, templates |
| `Sources/crc32c` | `src/crc32c` | `{include,src}/**/*.{h,cc}` + `LICENSE` |
| `Sources/leveldb` | `src/leveldb` | six folders of `{h,cc}` + `LICENSE` |
| `Sources/minisketch` | `src/minisketch` | `{include,src}/**/*.{h,cpp}` + `LICENSE` |
| `Sources/secp256k1` | `src/secp256k1` | `{include,src}/**/*.{h,c}` + `COPYING` |
| `Sources/libbitcoinkernel` | the folder root | both `COPYING` files, `src/**/*.h`, and the kernel source list |
| `Sources/bitcoind` | the folder root | `COPYING`, the remaining `src/**/*.cpp`, `src/wallet/**/*.h`, `src/ipc/exception.h` |
| `Tests/BitcoinTests/Fixtures` | `test/functional/data` → `rpc/`, `src/test/data` → `blockfilters/` | three JSON files |

**Patterns.** vendir's matcher expands braces, so `{include,src}/**/*.{h,cc}`
is one line. Library entries copy from their own upstream subfolder,
which removes `newRootPath`. The kernel source list is the exception to
brevity: it stays one path per line and appears twice, included under
`Sources/libbitcoinkernel` and excluded under `Sources/bitcoind`,
because vendir has no way to say "this list, negated". A drifted entry
puts a file in both targets (duplicate symbols) or neither (missing
symbols), so the build reports it. The list equals upstream's own
`bitcoinkernel` library definition in `src/kernel/CMakeLists.txt` plus
upstream's crypto library and `clientversion.cpp`.

**Patches.** Each `.patch` carries this repository's paths
(`Sources/bitcoind/src/init.cpp`). `rpc-server-reset.patch` touches one
file in each Bitcoin target and still applies as one unit. Because
patches run after the copy, the download folder stays unpatched, and
`git apply --check -p3 --directory=.vendir-upstream/bitcoin` tests a
patch against untouched upstream at any time.

**Hand-written files.** vendir empties each destination before copying;
`ignorePaths` keeps the project-owned files in place. Folders that are
wholly hand-written use a glob (`include/*` in both Bitcoin targets,
`src/bridge/*`), so a new bridge file survives without a config edit;
the rest are literal paths. A glob must match files only, since vendir
aborts when an `ignorePaths` match is a directory. Patched files are
deliberately not preserved: keeping their bytes across a sync would hide
a patch that no longer fits. One caveat remains: a future upstream file
landing at an `ignorePaths` destination would be shadowed by the local
one.

**No copies of upstream headers.** Two files that used to be duplicates
are one-line forwarding headers. `Sources/libbitcoinkernel/include/
bitcoinkernel.h` includes `../src/kernel/bitcoinkernel.h`; its
predecessor was a full copy with one extra nullability annotation that
`libbitcoinkernel.apinotes` already declares. `Sources/leveldb/include/
leveldb/helpers/memenv/memenv.h` includes the real header four levels
up, so `dbwrapper.cpp`'s `<leveldb/helpers/memenv/memenv.h>` resolves
through the target's public header folder.

**Test data.** vendir cannot merge two source folders into one
destination, so the files land in `Fixtures/rpc/` and
`Fixtures/blockfilters/`, and the three lookups in the tests name the
subfolder. `Package.swift`'s `.copy("Fixtures")` keeps the structure.

**CI job.** `vendir-check.yml` runs on PRs and pushes to `main` that
touch `vendir*.yml`, `patches/bitcoin/*.patch`, a vendored destination,
or the workflow, plus `workflow_dispatch`. `permissions: {}` at the
workflow level and `contents: read` on the job; `actions/checkout` with
`persist-credentials: false`, then `github-git-auth`. vendir is
installed by `curl` plus a hard-coded release SHA-256, pinned at 0.47.0.
The verify command is split into two steps so that only the download is
retried: `vendir sync --locked` through `retry-on-fetch-flake`, then
`git apply` and a `git status --porcelain` that must print nothing.
`git status` is used instead of `git diff --exit-code` because it also
reports untracked files, which is how a too-broad pattern shows up.

**What the job does not check.** A re-pointed upstream tag cannot change
a locked sync, because the lock pins the commit; it would surface as a
changed `sha:` in the lock diff of the next bump. A new upstream file
hidden behind an `ignorePaths` entry is not detected. Both can only
arise at a version bump, which the bump steps below cover by review.

**Bumping the pin.** Edit `ref:` in `vendir.yml`, run the sync, and read
the result: the lock diff should show only the intended commit; a patch
that no longer fits stops `git apply`; diff the three templates under
`.vendir-upstream/bitcoin` against the previous release's to see whether
a hand-written build-setting header needs a new entry; update the tag
string in `Sources/libbitcoinkernel/src/bitcoin-build-info.h`. Then
build, test, and open a PR. `minimumRequiredVersion` is a floor, not a
pin: run the vendir version the workflow pins.

## 6. Implementation steps

The remaining work is one design PR plus six implementation and closeout PRs,
all strictly sequential and all targeting `main`. Branches may be prepared
locally ahead of time, but a PR opens only after its predecessor merges. This
keeps every opened PR inside the existing CI triggers, which select pull
requests targeting `main`, and avoids rebasing a parallel stack after squash
merges. The slices are coherent repository states rather than one PR per
task:

1. **Design realignment** — correct this spec, record ADR 0012, mark ADR
   0010 superseded, and append the dated correction to ADR 0011.
2. **Header-copy cleanup** — replace the two hand-copied upstream headers
   with forwarding headers and delete the unused duplicated build-setting
   headers, while the existing script continues to perform a valid old-style
   sync.
3. **Fixture layout cleanup** — sync the three JSON fixtures into
   `Fixtures/rpc/` and `Fixtures/blockfilters/`, update their lookups, drop
   the unused fourth fixture, and remove the flattening fixup from the old
   script.
4. **Byte-preserving `vendir.yml` rewrite** — filter the download, copy
   libraries from their own upstream subfolders, use brace patterns and
   file-only `ignorePaths` globs, and prove the copied tree does not change.
5. **Patch relocation and script retirement** — rewrite the patches to
   `Sources/...` paths, delete `Scripts/vendor-sync.sh`, and update the
   operational documents that would otherwise still name it.
6. **CI freshness check** — add `vendir-check.yml` and its workflow
   inventory entry.
7. **Closeout** — finish explanatory documentation, validation reporting,
   roadmap/spec status, and generated indexes.

[tasks.md](./tasks.md) maps the tasks to those PRs and records the checkpoint
that must be true before the next PR opens.

## 7. Verification

Already true on `main` from the first two migration phases:

- [x] `Vendor/`, `subtree.yaml`, and the `swift-plugin-subtree` dependency
      are gone
- [x] `vendir.lock.yml` pins the commit `v31.0` resolves to, `6574cb40`

End-state checks still to earn in the ordered PRs:

- [ ] `vendir sync && git apply patches/bitcoin/*.patch` reproduces the six
      source trees and the test data byte for byte (`git status` shows
      nothing under those paths)
- [ ] The same commands with `--locked` reproduce that tree in CI, and
      `vendir-check.yml` passes on a GitHub runner
- [ ] Every `patches/bitcoin/*.patch` passes `git apply --check -p3
      --directory=.vendir-upstream/bitcoin` against the untouched download
      and `git apply -R --check` against `Sources/`
- [ ] `Scripts/vendor-sync.sh` is gone, and a bare `vendir sync` is the
      whole copy step
- [ ] `swift build --build-tests` and the non-embedded package tests pass in
      default and `wallet` configurations after the build-affecting slices
- [ ] The existing PR matrix passes with the forwarding headers and fixture
      layout: macOS tests including the isolated embedded-node suite, iOS,
      visionOS, tvOS, Linux Docker, DocC, and Tuist demo apps

## 8. Risks and mitigations

- **Fetch size.** Released vendir fetches every ref shallowly for a
  named tag (carvel-dev/vendir#453 is unshipped at 0.47.0), about 250 MB
  per sync. A local sync takes about 30 seconds. CI authenticates the
  fetch and bounds it with `github-git-auth`'s low-speed settings.
  Filtering the download saves disk, not transfer.
- **Forwarding headers reach outside the public header folder.** This
  holds while the package is built from source, which is the only way
  it ships. Packaging the headers alone into a binary framework would
  need real copies again.
- **A hand-written file outside `ignorePaths` is deleted by a sync.**
  `git status` shows the deletion, and the CI job fails on it.
- **Shadowed files.** See "What the job does not check".
- **Patch paths name this repository's folders.** A patched file that
  upstream moves between the two Bitcoin targets needs its patch path
  edited; `git apply` stops with an error when that happens.
- **Contributors need the vendir binary.** `brew install
  carvel-dev/carvel/vendir`; CI installs the pinned, hash-checked one.
- **The job is advisory.** It joins no required check without a
  maintainer decision, and its path filter would leave a required check
  pending on PRs that touch none of its paths.

## 9. Deferred work

- **GPG verification of the signed `v31.0` tag.** vendir's verifier
  still runs the frozen `x/crypto/openpgp` (carvel-dev/vendir#456
  unshipped); a CI-side `git verify-tag` against a committed keyring is
  the candidate follow-up.
- **Updater automation.** A bump stays `ref:` + sync + PR.
- **`vendir-check.yml` in the merge ruleset.** A maintainer decision;
  the path filter needs an always-run variant first.

## 10. Division of labor

Solo-maintainer infrastructure work. The seven PRs land strictly sequentially
rather than as a parallel stack: the repository's workflows test pull
requests targeting `main`, and sequential targeting preserves that pre-merge
evidence without changing CI behavior. The reference implementation and the
archived check-script experiment are evidence inputs, not merge candidates.
