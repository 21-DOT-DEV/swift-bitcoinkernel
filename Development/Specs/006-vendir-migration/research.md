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
- `vendir sync -d <path>` restricts a run to named directories — the
  recipe's stage-1 fetch-only step.

That rules the sibling's canonical "one `git:` per destination" out by
arithmetic: ~8 destinations × a several-hundred-MB pack per sync. The
Swift-ecosystem precedent for a GB-scale C/C++ upstream agrees:
`apple/swift-crypto`'s `scripts/vendor-boringssl.sh` (substantially adapted
from `grpc-swift`) clones the upstream once into a temp dir, wipes the
destination, copies a `PATTERNS` subset, applies committed `.patch` files,
then runs post-copy fixups — clone-once-slice-locally is the shape every
mature consumer of a huge C/C++ tree converges on. `swift-openssl`
implemented the same inside vendir (clone → slices) with a wrapper
executable and a provenance sidecar; ours is leaner because the cache
entry itself is a `git:` source, so `vendir.lock.yml` records the real
upstream commit SHA natively — no sidecar needed. The checkout also
doubles as the `git apply --check` target `patches/UPSTREAMING.md`
documents (previously `Vendor/bitcoin`). Alternatives:

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

## 3. Patch lifecycle — wipe + `git apply`, never `ignorePaths` for diffs

**Patched files sync fresh; `vendor-sync.sh` re-applies the five
`.patch` artifacts to the pristine checkout before slicing.** vendir wipes
each `directories[].path` before copying, so patched bytes cannot ride the
sync — they must be re-established. Re-apply is the only model with
packaging precedent:

- Debian `quilt` (`debian/patches/series`), RPM `%patch`, Gentoo `PATCHES`,
  Alpine APKBUILD, Yocto `SRC_URI += file://*.patch`, Bazel
  `http_archive(patches = [...])`, vcpkg/Homebrew `PATCHES`, npm
  `patch-package` — every system that keeps divergence *as patches*
  applies them mechanically after fetching pristine source, and the build
  fails visibly when upstream drifts underneath.
- Apple's `vendor-boringssl.sh` embeds patch application in the sync
  script itself — same wipe→copy→patch→fixup pipeline.
- The constitution's requirement ("MUST reapply patches after every
  extraction; extraction MUST NOT silently drop them") becomes mechanical:
  `git apply --check` failure aborts the sync with a named file.

`ignorePaths`-preserve (the sibling's model for its 4 hand-written shims)
was rejected for *patched* files specifically: preserving committed
patched bytes across the wipe makes a rotten patch invisible — upstream
changes underneath a frozen file and nothing notices until behavior
diverges. `ignorePaths` remains correct for the 21 files that are
project-owned with no upstream counterpart: six `module.modulemap`
stubs, the `include/` umbrella files in `bitcoind`/`libbitcoinkernel`,
the four `src/bridge/` shims, `bitcoin-build-{config,info}.h`,
`bitcoin-config.h`, `bitcoind.h`, and the two configure-generated
headers (`crc32c_config.h`, `port_config.h`). Two empirical constraints
from the first sync: entries must be literal FILE paths — vendir stats
each glob match and aborts on a directory (`include/**` matching
`include/config/` ended the run mid-wipe) — and preservation carries
working-tree bytes across the wipe but cannot resurrect an
already-deleted file.

Application locus: `--directory=.vendir-upstream/bitcoin` applies each
patch *whole* against the upstream-mirroring checkout — no per-file
routing needed even though `rpc-server-reset.patch` spans two extraction
destinations; the slices then distribute the patched bytes. The
`src/compat/compat.h` special-casing disappears: the subtree manifest
excluded it from the `src/**/*.h` rule so the patch could own the file;
under wipe+reapply it syncs normally and `main-function-guard.patch`
owns the delta.

## 4. Layout parity — a fixup stage for the two shapes vendir can't express

**Keep the current consumer-facing layout exactly; `vendor-sync.sh` runs
two post-slice fixups.** Verified constraints (vendir `config.go`):
managed `directories[].path`s may not overlap, and a `path: .` contents is
exclusive to its directory — so two vendir-unexpressible shapes exist:

- **Flat fixtures** — four JSONs live in *two* upstream dirs
  (`test/functional/data/rpc_{getblockstats,decodescript,psbt}.json` —
  verified the brace set resolves to exactly those three files at v31.0 —
  plus `src/test/data/blockfilters.json`) and must land flat in
  `Tests/BitcoinTests/Fixtures/`, which test code loads via
  `subdirectory: "Fixtures"`. They arrive repo-relative under
  `Fixtures/{test,src}/`; the fixup `mv`s the JSONs up and removes the
  skeleton dirs.
- **Synthetic memenv copy** — upstream ships `src/leveldb/helpers/memenv/
  memenv.h` only; `dbwrapper.cpp` includes `<leveldb/helpers/memenv/
  memenv.h>` through the `include/` public-headers root, so the repo
  carries a byte-copy at `Sources/leveldb/include/leveldb/helpers/memenv/
  memenv.h`. `ignorePaths`-preserving it would freeze an upstream file
  forever; `cp` from the freshly-synced `helpers/` copy keeps it tracking
  upstream.

Alternatives: **vendir-native layout change** (fixtures in
`Fixtures/rpc/` + `Fixtures/blockfilters/`, retargeting ~4
`subdirectory:` lookups) — rejected: the new shape is different but not
better, and the sibling's own rule applies — change layout only when the
new shape is better or equal-and-verifiable (it moved Wycheproof fixtures
because Tuist resource-flattening made the change free *and* cleaner; it
deduplicated `libsecp256k1Tests` because the new layout was strictly
better). Post-copy fixups are also a first-class stage in Apple's vendoring
script and in every distro `rules`/ebuild/makepkg — the normal answer when
a sync script already exists.

## 5. CI gate — adapted core, deferring the self-test suite

**Port the sibling's gate machinery minus the SHA-equality check and the
self-test harness, plus authenticated fetch.** What the research showed:

- **The industry-minimum gate is "regenerate and diff".** Kubernetes
  `hack/verify-vendor.sh` re-runs `go mod vendor` and fails on any diff;
  `npm ci --locked`, `cargo check --locked`, and Bazel's lockfile check
  are the same contract — the committed tree must reproducibly match the
  committed pin. That is the sibling's determinism check, promoted here
  to run the *whole recipe* (sync → `git apply` → fixups) before
  `git status --porcelain`, because bare `vendir sync` output is
  deliberately not the committed state.
- **Moved-tag detection** (remote ref ↔ lock resolution) is the accepted
  second layer — here `git ls-remote refs/tags/v31.0^{}` vs the locked
  SHA.
- **Apple runs none.** `apple/swift-crypto` has no vendor-verification
  workflow — drift surfaces only when someone re-runs
  `vendor-boringssl.sh`. The sibling's gate already exceeds that bar;
  shipping the core checks lands strictly above the industry minimum.
- **The sibling landed its own gate incrementally** — sync check first,
  workflow wiring second, allowlist/SHA-equality/ignorePaths probes later,
  self-test suite *last* (T025/T026). Option-1 mirrors that landing order.
- **Checks that adapt or drop**: the same-URL lock-SHA equality check is
  vacuous with one `git:` entry (the sibling had five same-URL entries to
  cross-compare); the `ignorePaths` shadow probe runs locally via `find`
  on the synced checkout instead of their curl-against-GitHub pattern —
  our preserve-set is literal file paths (directory globs abort the
  sync) and the cache is a full
  checkout; the config key-allowlist extends for `directory:`,
  `newRootPath`, `ignorePaths`, `legalPaths`.
- **Authentication is required, not optional**: the fetch is ~250 MB vs.
  the sibling's ~25 MB, anonymous shared-IP github.com throttling is
  documented in 005's research, and `github-git-auth` exists in-repo —
  it runs before the vendir step with `persist-credentials: false` on the
  checkout (the pairing rule from `.github/AGENTS.md`).

## 6. Lock semantics — annotated tag vs. peeled commit

`subtree.yaml`'s `commit: 84b62e1e8dbc9bbb393d0cb50c863b161b378f35` is the
*v31.0 tag object* (annotated, signed). `vendir.lock.yml` records what it
checked out — the peeled commit — so the two SHAs legitimately differ for
the same tree. The gate's resolve check therefore compares
`git ls-remote … refs/tags/v31.0^{}` (peeled) against the lock, not the
bare `v31.0` ref. `depth: 1` stays: the locked SHA is the tag tip and is
reachable at depth 1 under vendir's all-refs fetch.

## 7. Measured facts (local, at spec time)

- `Vendor/bitcoin` tracked: ~50 MB, 2,920 files (`git ls-files`), ~53 MB
  on disk; contains 363 `*.py` plus contrib/test tooling nothing
  extracts.
- `vendir version` locally: `0.47.0` (released 2026-11-16) —
  `minimumRequiredVersion` floor; sibling spec targeted 0.46.2.
- Destinations: 8 `directories[]` entries — 1 `git:` checkout + 6 source
  slices + 1 fixture slice.
- Preserve set (`ignorePaths`): 21 literal file entries — six
  modulemaps, config/build headers, four `src/bridge/` files, two
  configure-generated headers — verified against `git ls-files` per
  destination and by observed sync (the two generated headers surfaced
  as `D` in the parity check before being added).
- Upstream license files present at v31.0: `COPYING` (repo root +
  `src/secp256k1/` + `src/crypto/ctaes/`), `LICENSE` (`src/crc32c`,
  `src/leveldb`, `src/minisketch`) — each rides its slice with a
  matching `Package.swift` `exclude:`.
- Slice staging cost (unmeasured — jury observation): vendir copies each
  `directory.path` into staging *before* `includePaths` filtering, and
  the cache tree includes `.git/` (a several-hundred-MB pack), so one
  sync may stage the pack up to seven times on local disk. ADR 0011's
  "local copies" framing understates that. If a timed sync shows the
  cost material, `vendor-sync.sh` could rsync a `.git`-free export and
  point the slices at it (verified shape-identical on
  `Sources/crc32c`).

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
config headers (`bitcoin-config.h`, `bitcoin-build-{config,info}.h`,
`bitcoind.h`) are SPM-adapted substitutes upstream's build system never
produces. Regeneration would add a sync-time cmake dependency whose
host-specific probe answers re-derive what the committed files already
record.

**Steal: the drift tripwire.** `vendir-check.sh` should sha256 the
upstream templates feeding preserved/generated headers —
`src/crc32c/src/crc32c_config.h.in`, `src/leveldb/port/port_config.h.in`,
`cmake/bitcoin-build-config.h.in` — from the synced cache and compare
against recorded hashes; mismatch = "re-derive the config headers"
(our `lastRegenSha` analog, without the tool).

**Steal declined: restore-from-HEAD manifest.** `git checkout HEAD --`
always lands committed bytes; `ignorePaths` carries working-tree bytes.
Equivalent at 21 entries (the manifest pays off at 104), and the
locked-sync + clean-status gate catches stale worktree bytes anyway.
Their manual cache moots our stage-3 `-d` discipline (vendir never
touches `.vendir-cache/`); our `git:` cache keeps `vendir.lock.yml`
SHA provenance native — ADR 0011 stands.
