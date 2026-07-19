# Patches

Small modifications we maintain on top of the vendored Bitcoin Core sources. They exist for two reasons:

1. **In-process restart.** The `Bitcoin` product embeds `bitcoind` (Bitcoin Core's node daemon) inside iOS/macOS apps. An app stops, reconfigures, and restarts the node without relaunching itself — but four of Bitcoin Core's process-wide globals survive shutdown and crash the second start. Three patches make the cycle clean. Bitcoin Core's own fuzz-testing harness enforces the same no-leftover-state rule between its in-process test iterations, just not in the production shutdown path.
2. **Build compatibility.** Building with Swift Package Manager and against Apple's non-Mac SDKs needs two small source guards that change no behavior anywhere else.

Each patch is a pair of files: a `.md` write-up that opens with an info card (status, dependencies, how it gets filed upstream, which threads back it) and a `.patch` diff — the artifact of record, which must reapply cleanly after every source sync. No patch touches consensus code (the rules deciding which blocks and transactions are valid); see the [patch policy](../SECURITY.md#patch-policy).

Contributing one upstream? The order of work, the pre-written discussion thread, and the shared filing rules live in [`UPSTREAMING.md`](UPSTREAMING.md).

## The patches (Bitcoin Core v31.x)

All five are applied locally and none has been filed upstream yet. Per-patch status lives on each card.

### Restart support

1. **[Make the RPC server restartable](bitcoin/rpc-server-reset.md)** — `src/rpc/server.{cpp,h}` · [diff](bitcoin/rpc-server-reset.patch)
   Two shutdown functions guard themselves with one-shot locks that can never re-arm, so a second start trips assertions — and the lock also causes a separately reported startup crash that still reproduces. Both functions are naturally safe to call twice; the patch removes the locks and adds a small reset helper.

2. **[Reset four globals at shutdown](bitcoin/shutdown-reset.md)** — `src/init.cpp` · [diff](bitcoin/shutdown-reset.patch)
   Shutdown tears down everything except four process-wide globals, each of which greets the next start with a fatal assertion. The patch resets them at the end of shutdown, mirroring what Bitcoin Core's own test framework already does between in-process test runs.

3. **[Stop the late-log crash during teardown](bitcoin/logging-teardown-assertion.md)** — `src/logging.cpp` · [diff](bitcoin/logging-teardown-assertion.patch)
   The logger's teardown closes the log file but leaves the "write to file" switch on, so one late log line from a background thread aborts the process. One-line fix.

### Build compatibility

4. **[Let the host app own `main()`](bitcoin/main-function-guard.md)** — `src/compat/compat.h` · [diff](bitcoin/main-function-guard.patch)
   An embedding app already has a `main()`; Bitcoin Core's entry-point macro now sits behind a standard `#ifndef` guard so the build system can rename the daemon's entry to `bitcoind_main()`.

5. **[Compile the network-interface file on iPhone-family SDKs](bitcoin/ios-netif-guard.md)** — `src/common/netif.cpp` · [diff](bitcoin/ios-netif-guard.patch)
   One header this file includes ships only in the Mac SDK, so the file fails to compile for iPhone-family targets. The guard compiles that code only where the header exists (`__has_include`, the same idiom `randomenv.cpp` uses); Apple platforms without it take the existing unsupported-platform fallback.

## Verification memos

Records, not applied patches:

- [`cmake-ios-library-build.md`](bitcoin/cmake-ios-library-build.md) — proof that unmodified Bitcoin Core v31 builds its kernel library (`libbitcoinkernel.a`) for iOS device and simulator with stock CMake, plus validation of our committed build-configuration headers against real per-platform probes. Two recorded divergences (`HAVE_IFADDRS`, `HAVE_DECL_PIPE2`) are deliberately left unchanged pending a decision.
- [`tvos-execvp-feasibility.md`](bitcoin/tvos-execvp-feasibility.md) — why the `Bitcoin` product cannot build for tvOS (the SDK prohibits launching child processes) and the options if tvOS support is ever requested.

## Custom build files (not patches)

These are not upstream modifications but SwiftPM build-configuration files committed next to the vendored sources. They survive a source sync because the sync patterns in `subtree.yaml` only match `*.{h,c,cc,cpp}` code files.

**Build-configuration headers** — stand-ins for the header Bitcoin Core's CMake build would normally generate, with macOS-vs-iOS switches for the two probes that differ (`HAVE_GETENTROPY_RAND`, `HAVE_SYSTEM`; both validated against real CMake introspection — see the [CMake memo](bitcoin/cmake-ios-library-build.md)):

- `Sources/bitcoind/include/bitcoin-build-config.h`
- `Sources/libbitcoinkernel/src/bitcoin-build-config.h`

**Module-map stubs** (`module <name> { requires !cplusplus; export * }`) — tell SwiftPM not to auto-generate a module map for these C/C++ helper targets, which would otherwise break Linux builds under Swift's C++ interop mode:

- `Sources/secp256k1/include/module.modulemap`
- `Sources/crc32c/include/module.modulemap`
- `Sources/leveldb/include/module.modulemap`
- `Sources/minisketch/include/module.modulemap`

The stubs own no headers, so C++ code keeps resolving `#include "secp256k1.h"` and friends through ordinary include paths, and Swift code never imports these targets directly.

## swift-boost

Notes on our second vendored dependency, [swift-boost](https://github.com/21-DOT-DEV/swift-boost) (Boost C++ headers packaged for SwiftPM):

- [Inter-target dependencies](swift-boost/inter-target-deps.md) — a proposed upstream fix so Boost modules declare what they include, sparing consumers from listing 27 transitive modules by hand. Proposed; not yet filed.
- [Linux module compilation](swift-boost/linux-module-compilation.md) — resolved upstream in `pruned-umbrella-1.90.0`; kept as a short historical note.
