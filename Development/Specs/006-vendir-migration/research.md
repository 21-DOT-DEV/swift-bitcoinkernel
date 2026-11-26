# Research — 006 · Migrate Bitcoin Core vendoring from subtree extraction to vendir

Evidence and rejected alternatives for [the plan](./plan.md); ordered work
in [tasks.md](./tasks.md). Blueprint repo: `21-DOT-DEV/swift-secp256k1`
spec `Development/Specs/002-vendir-migration` (read in full — `plan.md`,
`research.md`, `tasks.md` — before this file was written; its decisions were
re-derived, not copied, because this repository's shape differs on every
axis the sibling's choices depended on).

## 1. Vendir vs. keeping the subtree stack

**Vendir, with the committed `Vendor/` mirror deleted.** The subtree stack
costs a 53 MB mirror of the *entire* upstream repo — 2,920 tracked files —
to feed extraction rules that pull ~14 MB of it into `Sources/`; the rest
(363 Python scripts, `contrib/`, `test/functional/` drivers, `.github/`,
Qt assets) is dead weight in every clone. `subtree.yaml` extraction is a
maintainer-local step with no lockfile: the only recorded provenance is
the `commit:` field naming the *tag object* SHA and whatever the squash
commit trailer captured. The sibling repo reached the same conclusion for
its five small vendored inputs. Alternatives considered:

- **Keep subtree + `swift-plugin-subtree`** — rejected: the plugin is an
  in-house dev tool whose value was never CI-integrated here (no subtree
  workflows exist to port); vendir provides declarative config, a
  committed lock, and a maintained upstream.
- **Upstream-style committed `git subtree` mirror retained as the
  source-of-truth** — rejected: Bitcoin Core itself keeps `src/leveldb`
  etc. as committed subtrees because Core developers patch *inside* them
  and the changes flow upstream (bidirectional). This repository is a
  one-directional consumer: local diffs live as `.patch` artifacts in
  `patches/`, applied downstream of extraction. A mirror earns nothing a
  gitignored checkout can't provide.

## 2. Fetch shape — one `git:` checkout + `directory:` slices

**Single `git:` contents entry into `.vendir-upstream/bitcoin`; every
extraction destination is a `directory:` slice of that checkout.**
Decided by vendir's fetch internals, verified in the v0.47.0 source:

- Each `git:` contents entry performs its own fetch; there is no
  cross-entry object cache (carvel-dev/vendir#101).
- For a named tag, released vendir still fetches *every* ref shallowly —
  `remote.origin.tagOpt --tags` plus shallow fetch flags — so "one tag"
  pulls bitcoin/bitcoin's ~715 refs ≈ a several-hundred-MB pack
  (carvel-dev/vendir#453's targeted fetch is not in any release,
  including today's v0.47.0 which is installed locally and sets the
  `minimumRequiredVersion`).
- `directories[]` sync in config order; `directory:` sources copy local
  paths (fields verified: `path`, `directory.path`, `includePaths`,
  `excludePaths`, `ignorePaths`, `legalPaths`, `newRootPath`).
- `includePaths` on the `git:` entry filters what the download folder
  keeps, and a `directory:` source may point at a subfolder of it
  (`.vendir-upstream/bitcoin/src/leveldb`), which removes `newRootPath`
  from the library entries. Both verified by sync at 0.47.0.

That rules the sibling's canonical "one `git:` per destination" out by
arithmetic: ~8 destinations × a several-hundred-MB pack per sync. The
Swift-ecosystem precedent for a GB-scale C/C++ upstream agrees:
`apple/swift-crypto`'s `scripts/vendor-boringssl.sh` (substantially adapted
from `grpc-swift`) clones the upstream once into a temp dir, wipes the
destination, copies a `PATTERNS` subset, applies committed `.patch` files,
then runs post-copy fixups — clone-once-slice-locally is the shape every
mature consumer of a huge C/C++ tree converges on. `swift-openssl`
implemented the same inside vendir (clone → slices) with a wrapper
executable and a provenance sidecar; ours is leaner because the download
entry itself is a `git:` source, so `vendir.lock.yml` records the real
upstream commit SHA natively — no sidecar needed. The download folder
is also what `patches/UPSTREAMING.md` checks patches against
(previously `Vendor/bitcoin`); it is never patched, so it is untouched
upstream at all times. Alternatives:

- **~8 `git:` entries, one per destination** — the sibling's shape;
  rejected on fetch economics (their total upstream is ~25 MB across five
  small repos).
- **`http:` tarball cache + slices** — ~15 MB per sync but provenance
  degrades to a tarball sha256: the CI gate could no longer re-resolve the
  named ref to a commit, and GitHub-generated archives have changed
  checksums historically (the 2023 `git archive` compression change).
  Apple's scripts pin by *revision* for the same reason.
- **GitHub REST archive + `gh`** — same tarball problem plus an API quota
  the git protocol doesn't carry.

## 3. Patch lifecycle — re-apply after the copy, never `ignorePaths` for diffs

**Patched files sync fresh, and `git apply patches/bitcoin/*.patch` runs
after `vendir sync`, directly onto `Sources/`.** vendir empties each
destination before copying, so patched bytes cannot ride the sync and
must be re-established. Re-applying patch files is the only model with
packaging precedent:

- Debian `quilt`, RPM `%patch`, Gentoo `PATCHES`, Yocto `SRC_URI +=
  file://*.patch`, Bazel `http_archive(patches = [...])`, npm
  `patch-package`: every system that keeps divergence as patches applies
  them mechanically after fetching pristine source, and fails visibly
  when upstream drifts underneath.
- The constitution's requirement ("MUST reapply patches after every
  vendor sync; the sync MUST NOT silently drop them") is mechanical: a
  patch that no longer fits stops `git apply` and names the file.

**Where the patches apply: the copy, not the download.** vendir has no
patch or post-sync step (carvel-dev/vendir#250 is open), so a patch step
is a second command either way. Applying to the download between the
fetch and the copies forces three ordered stages and a script, makes a
bare `vendir sync` produce a wrong tree, and leaves the download holding
patched files. The tools that copy an upstream into a different layout
all patch the copy:

- Apple's `scripts/vendor-boringssl.sh` (swift-crypto, swift-nio-ssl)
  copies a filtered subset into `Sources/CCryptoBoringSSL`, then runs
  plain `git apply`; its patch files carry `Sources/CCryptoBoringSSL/...`
  paths.
- Firefox's `mach vendor` applies `patches:` "after vendoring", with
  patch paths "relative to the vendor-directory rather than the gecko
  root directory".
- dfetch keeps patches relative to the vendored folder and has a
  separate `dfetch format-patch` command to convert one to upstream form.

Our analog of that conversion is `git apply -p3`, which strips
`a/Sources/<target>/` back to upstream's `src/...`. Both Bitcoin targets
sit three path parts deep, so one strip level serves every patch,
including `rpc-server-reset.patch`, which spans the two.

`ignorePaths` for patched files was rejected: preserving committed
patched bytes across the sync makes a rotten patch invisible. It remains
correct for files that are project-owned with no upstream counterpart:
module-map stubs, build-setting headers, the Swift bridge sources, the
apinotes file, and the two forwarding headers (§4). Two empirical
constraints: an `ignorePaths` glob must match files only, because vendir
aborts on a directory match, and preservation carries working-tree
bytes, so it cannot resurrect a file already deleted.

## 4. Layout — two shapes vendir can't express, removed instead of fixed up

vendir's managed `directories[].path`s may not overlap, and a `path: .`
contents entry is exclusive to its directory. Two shapes in the
subtree-era layout therefore could not come from a sync alone. Both are
changed so that no post-sync step exists:

- **Test data.** The JSON files live in two upstream folders
  (`test/functional/data/` and `src/test/data/`) and used to land flat
  in `Tests/BitcoinTests/Fixtures/`. They now sync into `Fixtures/rpc/`
  and `Fixtures/blockfilters/` through two contents entries, and the
  three test lookups name the subfolder. `rpc_psbt.json` was synced but
  read by no test, and is dropped. Syncing is worth keeping: the two
  `rpc_` files are upstream's own expected RPC output, so refreshing
  them at each bump is what lets the decode tests notice a changed
  shape. The same advice comes from Wycheproof's README ("setting up
  automation to track changes"), and btclib-benchmarks issue 404
  documents hand-copied vectors falling behind unnoticed.
- **`memenv.h`.** Upstream ships `src/leveldb/helpers/memenv/memenv.h`
  only; `dbwrapper.cpp` includes `<leveldb/helpers/memenv/memenv.h>`,
  which upstream resolves from `src/` and this package must resolve
  from LevelDB's public header folder. The file at
  `Sources/leveldb/include/leveldb/helpers/memenv/memenv.h` is a
  hand-written one-line forwarding header, not a copy, so it cannot go
  stale and needs no `cp`.

The same treatment applies to a third file that predates the migration:
`Sources/libbitcoinkernel/include/bitcoinkernel.h` was a full copy of
`src/kernel/bitcoinkernel.h` with one added nullability annotation,
kept across syncs by `ignorePaths`. A stale copy would have Swift call
C functions as the old release declared them, which nothing detects at
compile time. It is now a forwarding header, and the annotation it
carried is already in `libbitcoinkernel.apinotes`. Apple's vendoring
script never hand-keeps such copies either: it deletes and regenerates
its public header folder on every run.

Verified on the reference implementation: a macOS `swift build
--build-tests` plus the kernel test suite, the wallet-trait variant, and
an iOS `xcodebuild` build all pass with both forwarding headers, and the
compiler's dependency records show Swift reaching the vendored header
through the forwarding line.
The build reads public headers in place; no build product holds a copy.

## 5. CI check — re-run the sync and require no difference

**One workflow, no check script.** The industry-minimum gate for
committed vendored files is "regenerate and diff": Kubernetes'
`hack/verify-vendor.sh` re-runs its vendoring script and fails on any
difference, OpenShift runs `make vendor && git diff --exit-code`, and
Firefox's `vendor-verify` job re-vendors at the pinned revision and
requires a match. Apple's swift-crypto runs none. Because the sync here
is two plain commands, the workflow can run them directly:

- `vendir sync --locked`, then `git apply patches/bitcoin/*.patch`, then
  `git status --porcelain` must print nothing. `git status` is used
  because `git diff --exit-code` ignores untracked files, a documented
  gap in this pattern.
- **Moved tag.** The lock pins the commit, and `--locked` syncs from it,
  so a re-pointed tag cannot change what the check reproduces (the
  March 2025 `tj-actions/changed-files` compromise spared exactly the
  consumers pinned to a commit). It would show as a changed `sha:` at
  the next bump.
- **Config typos.** vendir ignores unknown keys silently, but a
  misspelled filter changes which files are copied, and the comparison
  reports that.
- **Shadowed files.** A new upstream file landing at an `ignorePaths`
  destination is the one case the comparison cannot see. It can only
  arise at a version bump.

An earlier design put five named checks in a `Scripts/vendir-check.sh`
(key allowlist, tag resolution, recipe replay, shadow probe, dual-list
equality), following the sibling repository, whose version runs to
about 2,000 lines of shell including its own tests. It was dropped: the
replay is this workflow, the lock covers the tag, the build reports a
dual-list mismatch as duplicate or missing symbols, and the shadow
probe alone does not justify the script.

**Authentication is required, not optional**: the fetch is ~250 MB,
anonymous shared-IP github.com throttling is documented in 005's
research, and `github-git-auth` exists in-repo. vendir clones with the
system git and inherits the environment, so the header the action
writes to `~/.gitconfig` applies. The download step retries through
`retry-on-fetch-flake`; the comparison step never retries.

## 6. Lock semantics — annotated tag vs. peeled commit

`subtree.yaml`'s `commit: 84b62e1e8dbc9bbb393d0cb50c863b161b378f35` is the
*v31.0 tag object* (annotated, signed). `vendir.lock.yml` records what it
checked out — the peeled commit — so the two SHAs legitimately differ for
the same tree. To compare by hand, use the peeled form:
`git ls-remote … refs/tags/v31.0^{}` equals the lock's `sha:`, and the
bare `v31.0` ref does not. `depth: 1` stays: the locked SHA is the tag tip and is
reachable at depth 1 under vendir's all-refs fetch.

## 7. Measured facts (local, at spec time)

- `Vendor/bitcoin` tracked: ~50 MB, 2,920 files (`git ls-files`), ~53 MB
  on disk; contains 363 `*.py` plus contrib/test tooling nothing
  extracts.
- `vendir version` locally: `0.47.0` (released 2026-11-16) —
  `minimumRequiredVersion` floor; sibling spec targeted 0.46.2.
- Destinations: 8 `directories[]` entries — 1 `git:` download + 6 source
  trees + 1 test-data entry with two contents.
- Sync time: about 30 seconds locally for the full `vendir sync`,
  fetch included. The download folder is 22 MB filtered, against
  177 MB for the full checkout with its `.git`.
- Committed files the macOS build never read, from the compiler's
  dependency records: three hand-written headers (two copies of a
  `bitcoin-config.h` that nothing includes, and `bitcoind`'s duplicate
  `bitcoin-build-info.h`), now deleted. Upstream headers are almost all
  read, so `src/**/*.h` is already tight.
- Preserve set (`ignorePaths`): globs for the wholly hand-written
  folders (`include/*` in both Bitcoin targets, `src/bridge/*`) and
  literal paths elsewhere: the four library module maps, the two
  generated-from-template headers (`crc32c_config.h`, `port_config.h`),
  the kernel's two `bitcoin-build-*.h` files, and the `memenv.h`
  forwarding header.
- Upstream license files present at v31.0: `COPYING` (repo root +
  `src/secp256k1/` + `src/crypto/ctaes/`), `LICENSE` (`src/crc32c`,
  `src/leveldb`, `src/minisketch`) — each rides its slice with a
  matching `Package.swift` `exclude:`.
- Copy staging cost: vendir copies each `directory.path` into staging
  before filtering. Measured at about one second per entry against the
  full 177 MB checkout, and less against the filtered folder.

## 8. Cross-reference — swift-openssl's generation machinery (PR 16)

`21-DOT-DEV/swift-openssl` PR 16 runs a `VendirSync` Swift tool: a manual
`git clone` into `.vendir-cache/` (not a vendir `git:` entry),
`directory:`-only slices, then `git checkout HEAD --` over a 104-path
`scripts/vendir-preserve.txt` manifest. Its `--regenerate` mode runs
OpenSSL's own `./Configure` + `make` (with `SOURCE_DATE_EPOCH` pinned)
inside the cache to reproduce ~100 configure-generated artifacts —
including most of `providers/implementations/**`, which upstream ships
only as `.c.in` templates — and a `lastRegenSha` field in
`vendir-upstream.json` trips when the upstream sha moves without a
regenerate.

**Generation rejected at our scale.** Verified against the v31.0 cache:
the committed `crc32c_config.h` is straight `#cmakedefine01`
substitution of `src/crc32c/src/crc32c_config.h.in` with arm64 answers
baked (`HAVE_ARM64_CRC32C 1`); `port_config.h` is substitution of
`src/leveldb/port/port_config.h.in` plus a hand-appended
`LEVELDB_IS_BIG_ENDIAN` block the template does not contain — even a
cmake-driven regenerate could not reproduce it verbatim. The remaining
config headers (`bitcoin-build-{config,info}.h`, `bitcoind.h`) are
SPM-adapted substitutes upstream's build system never
produces. Regeneration would add a sync-time cmake dependency whose
host-specific probe answers re-derive what the committed files already
record.

**Kept from it: the templates.** The hand-written build-setting
headers derive from three upstream templates:
`src/crc32c/src/crc32c_config.h.in`, `src/leveldb/port/port_config.h.in`
and `cmake/bitcoin-build-config.h.in`. The download filter keeps all
three in `.vendir-upstream/bitcoin`, so a bump can diff them against
the previous release's to see whether a header needs a new setting.

**Not taken: the restore-from-HEAD manifest.** `git checkout HEAD --`
always lands committed bytes; `ignorePaths` carries working-tree bytes.
The two are equivalent at this file count, and the locked sync plus
clean-status check catches stale working-tree bytes anyway.

## 9. Delivery shape — design first, then six sequential implementation PRs

**Design first.** Substantial tooling changes are normally reviewed as design
before implementation: Kubernetes Enhancement Proposals move to
`implementable` before implementation starts, and Rust's RFC process can
reject implementation PRs that arrive without the RFC. This repository's
equivalent artifact is the corrected Spec 006 set, so the first PR is
documentation and decision records only. It is not a waterfall step: the
reference implementation already exists as proof, and the design PR records
what that proof taught.

**Small means coherent, not one task per PR.** Linux's patch guidance asks
for one logical change per patch, permits explicit dependencies, and expects
the tree to build and run after each patch. Google, GitHub, and Microsoft's
review guidance all prefer small focused changes without treating line count
alone as the unit. Applied here, forwarding headers, fixture layout, the
byte-preserving `vendir.yml` rewrite, patch relocation, CI, and closeout are
separate slices. Splitting them further creates diffs that are smaller but
not independently valid states.

**Sequential, not stacked.** GitHub now documents stacked PRs and LLVM
recommends dropping target-branch restrictions when a project uses them, but
Thoughtworks keeps the technique in "Caution" because it can substitute for
real decomposition. This repository's existing workflows run pull requests
only when they target `main`; a parallel stack targeting predecessor branches
would therefore lose the package, Docker, and Tuist evidence unless the
workflow triggers were broadened first. Since the decomposition already makes
each PR independently reviewable and a solo maintainer does not need parallel
review lanes, the series lands strictly sequentially against `main` instead.

**Validation depth.** LLVM and Kubernetes expect meaningful local
verification before submission; Google and AWS make the complementary point
that expensive or environment-specific tests belong in automated pre-merge
gates when local duplication creates too much friction. GitHub's
`pull_request` workflows also test the proposed merge ref, which a local
branch build does not exactly reproduce. The selected policy is therefore
risk-tiered: broad local package build/test evidence for build-affecting
slices, exact sync replay for recipe slices, actionlint for workflow slices,
and the existing full platform/application matrix in pre-merge CI.

## 10. Rejected performance idea — vendir's git-bundle cache

The archived check-script branch carried a promising operational idea: set
`VENDIR_CACHE_DIR` and `VENDIR_MAX_CACHE_SIZE` so vendir's git-bundle cache
would avoid repeating the large Bitcoin Core fetch. The mechanism exists in
vendir 0.47.0 — its git fetcher writes a bundle under
`.vendir-cache/fetcher/git-bundle/`, keyed by upstream URL — but validation
rejected the idea for this repository:

- Cold locked sync with the cache enabled: 29 seconds; warm locked sync with
  the 122 MB bundle present: 33 seconds. The two filtered output trees were
  byte-identical, so the comparison itself was valid.
- A probe that unbundled the cache and then ran the same shallow fetch still
  downloaded 42,844 objects in 35 seconds. After the same repository had real
  local refs from an ordinary fetch, the next fetch took 3 seconds and
  downloaded 1,044 objects.
- The mechanism explains the result: `git bundle unbundle` is plumbing that
  imports objects and prints the refs; it does not update the repository's
  refs. Fetch negotiation advertises "haves" from refs, so the imported
  objects are invisible to the following fetch. vendir also rewrites the
  122 MB bundle after every sync, which consumes the time the cache was
  meant to save.

The cache therefore is not documented as part of the sync. This does not
change the fetch-shape decision in §2; it only means each sync still pays the
large shallow fetch until a vendir release ships targeted fetch behavior.
