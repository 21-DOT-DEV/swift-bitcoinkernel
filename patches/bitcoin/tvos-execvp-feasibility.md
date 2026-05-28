# Feasibility: bitcoind on tvOS without `execvp`

A scoping analysis, not a finalized patch. Asks one question: can the embedded `bitcoind` we ship in the `Bitcoin` product run on tvOS, given that `execvp(3)` is `__TVOS_PROHIBITED` in the tvOS SDK and currently blocks the build?

## Why this comes up

Building the `Bitcoin` product for tvOS fails at compile time:

```
.../Sources/bitcoind/src/util/exec.cpp:24:12: error: 'execvp' is unavailable: not available on tvOS
   24 |     return execvp(file, argv);
      |            ^
.../AppleTVOS26.4.sdk/usr/include/unistd.h:458:
  458 | int      execvp(...) __WATCHOS_PROHIBITED __TVOS_PROHIBITED;
```

The `BitcoinKernel` product builds for tvOS without changes (verified — CI now exercises it via `apple-builds.yml`). `Bitcoin` is the only tvOS-blocked product.

## Where `execvp` lives in our extraction

Three places in `Sources/bitcoind/` and `Sources/libbitcoinkernel/` reference subprocess execution:

| File | What it does | tvOS-relevant? |
| --- | --- | --- |
| `Sources/bitcoind/src/util/exec.cpp:24` | `util::ExecVp()` — thin wrapper around `execvp(3)` on POSIX, `_wexecvp` on Windows | Direct compile failure on tvOS |
| `Sources/libbitcoinkernel/src/util/subprocess.h:1178, 1307` | `subprocess::Popen` — fork+exec wrapper for `RunCommandParseJSON` | Template inline; not instantiated unless `ENABLE_EXTERNAL_SIGNER` is defined |
| `Sources/bitcoind/src/common/run_command.cpp:28` | `RunCommandParseJSON` — gated behind `#ifdef ENABLE_EXTERNAL_SIGNER`, throws "Compiled without external signing support" otherwise | Dead unless the external-signer build option is on |

## Who actually calls these in our build

`util::ExecVp` has **zero call sites** in our extracted sources. The only caller in upstream Bitcoin Core is `Vendor/bitcoin/src/bitcoin.cpp` — the unified multicall binary entry point that dispatches to `bitcoin-cli` / `bitcoin-tx` / `bitcoin-wallet` / `bitcoin-util` by re-exec'ing the right helper. That file is NOT in `subtree.yaml`'s extraction set; we ship only the `bitcoind` entry point (`bitcoind_main`, renamed via `MAIN_FUNCTION`), not the multicall dispatcher.

`subprocess::Popen` is instantiated only inside `RunCommandParseJSON` (`run_command.cpp:28`). That whole function body is `#ifdef ENABLE_EXTERNAL_SIGNER` — without the define, it throws and the Popen template never instantiates, so `fork()` and `execvp()` inside it never get codegen'd. `ENABLE_EXTERNAL_SIGNER` is **not** defined anywhere in our `Package.swift` (verified — see `CXXSetting.bitcoinSettings`).

`external_signer.cpp` uses `subprocess::util::split` — a string-splitting helper, not a process launcher. No fork/exec involved.

## Runtime answer

**Yes — `bitcoind` can run end-to-end without `execvp`** in the configuration we ship:

- The multicall-dispatch path that uses `util::ExecVp` doesn't exist in our binary
- The external-signer code path that uses `subprocess::Popen` is compiled out via `#ifdef`
- The Bitcoin Core consensus, mempool, P2P, RPC server, and (with the `wallet` trait) wallet subsystems do not depend on subprocess execution at runtime

This is consistent with the fact that an embedded `bitcoind` running inside a single-process Swift binary has no use for re-exec'ing or for launching helper binaries — both are inherently multi-process patterns that the embedded model doesn't fit.

## Compile-time answer

Compile fails because `clang` rejects the `execvp(...)` call expression as an availability violation. The check fires on **use**, not on declaration, so just including `<unistd.h>` is fine. The minimal fix needs to make the call expression not appear in tvOS compilation.

## Patch options

### Option A — `#if !TARGET_OS_TV` guard around the `execvp` call (recommended)

Mirror the existing pattern in [`ios-netif-guard.md`](ios-netif-guard.md): use Apple's `<TargetConditionals.h>` to skip the prohibited call on tvOS, leaving every other platform untouched.

```cpp
// Sources/bitcoind/src/util/exec.cpp
#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

int ExecVp(const char* file, char* const argv[])
{
#if defined(__APPLE__) && TARGET_OS_TV
    // execvp is __TVOS_PROHIBITED; ExecVp is unreachable in the embedded
    // bitcoind build (no multicall dispatcher in this extraction).
    errno = ENOSYS;
    return -1;
#elif !defined(WIN32)
    return execvp(file, argv);
#else
    // existing Windows branch unchanged
#endif
}
```

- **Pros:** minimal diff; runtime semantics on tvOS are "stub that fails loudly if anyone ever calls it" (`errno = ENOSYS`); zero impact on any other platform; survives subtree sync via `patches/bitcoin/` storage.
- **Cons:** patches a vendored file. The pattern is established (see `ios-netif-guard.md`, `main-function-guard.md`).
- **Upstream story:** small, mechanical, and parallel to the existing iOS guard — plausibly mergeable upstream as a tvOS portability fix.

### Option B — exclude `util/exec.cpp` entirely on tvOS

SwiftPM's `Target.exclude` is `[String]` and **does not** support `.when(platforms:)`. So this can't be expressed cleanly in `Package.swift` without a workaround (e.g. an unconditional exclude plus a separate per-platform stub). Rejected as more invasive than Option A.

### Option C — guard via a build-system `#define`

Add `.define("BITCOINKERNEL_NO_EXECVP", to: "1", .when(platforms: [.tvOS]))` to `Package.swift` and patch the .cpp to gate on that. Functionally equivalent to Option A but uses our build define rather than Apple's `TargetConditionals.h`. Slightly more brittle because it requires two coordinated changes; Option A is self-contained in the .cpp patch.

## Recommendation

**Adopt Option A** when (and only when) tvOS support for the `Bitcoin` product becomes a real consumer ask. Until then, the `Bitcoin` product is excluded from the tvOS CI job by scheme (see `.github/workflows/apple-builds.yml`), `BitcoinKernel` covers the consensus-validation use case on tvOS, and SwiftPM consumers who try to add `Bitcoin` to a tvOS target get a clear compile error pointing at the prohibited call.

The patch is small enough to land in one commit; the upstream PR would be 5-10 lines. Not a launch blocker.

## What would break this analysis

- **Enabling `ENABLE_EXTERNAL_SIGNER`** in `CXXSetting.bitcoinSettings`. That activates `RunCommandParseJSON` and instantiates `subprocess::Popen`, pulling `fork()`/`execvp()` into codegen. The Popen calls are also `__TVOS_PROHIBITED`, so the build would fail for additional reasons. Out of scope as long as external signing remains off.
- **Re-extracting `Vendor/bitcoin/src/bitcoin.cpp`** (the multicall dispatcher) into `Sources/bitcoind/src/`. That file calls `util::ExecVp` directly and was deliberately left out by `subtree.yaml`. Including it would make `ExecVp` reachable at runtime and the stub from Option A would break the multicall feature on tvOS — though the multicall binary isn't a use case for an embedded `bitcoind` anyway.
- **A future upstream change that adds another `execvp`/`fork`/`posix_spawn` call into a code path we extract**. Subtree sync would reintroduce the problem. Discovered via the tvOS CI job (which would start failing), then re-evaluated.

## Open questions for upstream discussion

- Is there appetite upstream for a `__TVOS_PROHIBITED`-aware guard, given iOS already has the `ios-netif-guard.md` precedent? The Bitcoin Core developers have historically been conservative about non-server-OS portability changes; framing the PR around the libbitcoinkernel library-extraction effort (#24303) — same framing used in `ios-netif-guard.md` — would be the natural angle.
- Should the stub return `ENOSYS` (chosen above) or `EPERM`? `ENOSYS` ("function not implemented") more accurately reflects "compiled out on this platform"; `EPERM` ("operation not permitted") would imply runtime permission denial. `ENOSYS` is more honest about the build configuration.
