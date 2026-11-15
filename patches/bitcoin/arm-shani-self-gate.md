# Let flat build systems define `ENABLE_ARM_SHANI` once

Upstream enables the ARMv8 SHA-2 implementation (`src/crypto/sha256_arm_shani.cpp`, added by [#24115](https://github.com/bitcoin/bitcoin/pull/24115)) only when a CMake probe proves `-march=armv8-a+crypto` compiles its intrinsics, and passes that flag to the one file that needs it. Build systems that can't set per-file flags — SwiftPM, Bazel, vendored source lists — can only define `ENABLE_ARM_SHANI` for every architecture at once, which makes `sha256.cpp`'s dispatch block reference ARM symbols in x86 objects and the implementation file fail to compile `<arm_neon.h>` off-ARM entirely. The patch makes both sites self-gate, the same idiom `sha256_sse4.cpp` already uses: wrong-target files compile to empty objects. It is a no-op in the CMake build — there `ENABLE_ARM_SHANI` is only ever set where the probe already succeeded, which implies every added macro is true.

| | |
|---|---|
| **Status** | Applied here; not yet filed upstream. |
| **Touches** | `src/crypto/sha256.cpp`, `src/crypto/sha256_arm_shani.cpp` |
| **Depends on** | Nothing. |
| **File as** | Direct pull request — a "file anytime" standalone filing in [the pipeline](../UPSTREAMING.md#the-pipeline): inert in the CMake build, unlocks a class of downstream builds. |
| **PR title** | `crypto: let the ARMv8 SHA-2 files self-gate on target capability` |
| **Cite** | [#24115](https://github.com/bitcoin/bitcoin/pull/24115) — the feature being unlocked; [#27587](https://github.com/bitcoin/bitcoin/issues/27587) — the kernel-library tracker, as context that flat downstream builds are a live, supported direction. |

## The change

```diff
diff --git a/src/crypto/sha256.cpp b/src/crypto/sha256.cpp
--- a/src/crypto/sha256.cpp
+++ b/src/crypto/sha256.cpp
@@ -651,7 +651,7 @@
 #endif
 #endif // defined(HAVE_GETCPUID)
 
-#if defined(ENABLE_ARM_SHANI)
+#if defined(ENABLE_ARM_SHANI) && (defined(__aarch64__) || defined(__arm__))
     bool have_arm_shani = false;
     if (use_implementation & sha256_implementation::USE_SHANI) {
 #if defined(__linux__)
diff --git a/src/crypto/sha256_arm_shani.cpp b/src/crypto/sha256_arm_shani.cpp
--- a/src/crypto/sha256_arm_shani.cpp
+++ b/src/crypto/sha256_arm_shani.cpp
@@ -8,7 +8,7 @@
 // Barry O'Rourke for the mbedTLS project.
 // Variant specialized for 64-byte inputs added by Pieter Wuille.
 
-#ifdef ENABLE_ARM_SHANI
+#if defined(ENABLE_ARM_SHANI) && (defined(__ARM_FEATURE_CRYPTO) || defined(__ARM_FEATURE_SHA2))
 
 #include <array>
 #include <cstdint>
```

This is the `.patch` artifact verbatim; it applies cleanly to the vendored v31.0 tree and to the extracted copies under `Sources/libbitcoinkernel/src/crypto/` (verified on this branch — see Notes).

## Writing the PR

> Flat build systems (SwiftPM, Bazel, vendored source lists) can only define `ENABLE_ARM_SHANI` for every architecture at once, because they cannot pass `-march=armv8-a+crypto` per file. Gate the dispatch block on an ARM target macro and the implementation file on its crypto feature macros, so non-ARM objects compile empty — the same self-gating idiom `sha256_sse4.cpp` already uses. No behavior change in the CMake build.

Rules it follows: mechanical claims only; no "we need this for our package" narrative; every claim verifiable against master in seconds.

## If reviewers push back (for replies, in your own words — not the description)

**"Why isn't the dispatch block gated on `__ARM_FEATURE_CRYPTO` too?"** The dispatcher translation unit is deliberately compiled *without* `-march=armv8-a+crypto` — it emits no crypto instructions itself, it only calls them — so the feature macro is absent there in exactly the builds the flag exists for (e.g. aarch64 GCC at the armv8-a baseline). A feature gate in `sha256.cpp` would silently dead-code the ARM dispatch on Linux ARM. The arch macro is the condition that is true in both build models: on every ARM build upstream produces, and false on every non-ARM slice a flat build produces.

**"Doesn't that leave a gap — arch on, feature off?"** In a flat build defining `ENABLE_ARM_SHANI` on crypto-less aarch64, dispatch compiles in while the impl is empty — a link error. That configuration is already ill-formed without the patch (upstream's contract for `ENABLE_ARM_SHANI` is "the impl file was compiled with crypto flags"); the patch makes the failure loud and early instead of producing wrong-symbol references. Our own define is scoped to Apple platforms, where every arm64 toolchain ships the crypto baseline, so the gap can't arise here.

**"Why aren't `_M_ARM64`/`_M_ARM` in the arch test?"** MSVC can't satisfy the impl side: it defines no ACLE `__ARM_FEATURE_*` macros, and it ships `arm64_neon.h` where the file includes `<arm_neon.h>` — so admitting MSVC's arch macros in the dispatcher would recreate the exact dispatch-on/impl-off link gap the impl gate exists to close. Every toolchain that can compile the impl file (GCC, Clang, armclang — clang-cl included) defines `__aarch64__`/`__arm__`.

**"Why `__ARM_FEATURE_SHA2` in addition to `__ARM_FEATURE_CRYPTO`?"** The file uses only SHA-256 intrinsics; newer toolchains can expose `+sha2` without the legacy crypto bundle. Either macro means the TU may emit them.

**"Does this change the hashes or the selection logic?"** Neither. Every implementation `Transform` can point at is upstream's own code, `SelfTest()` still runs on detection, and the `getauxval`/`sysctlbyname` runtime checks are untouched.

## Notes

Companion build-system changes (outside this patch, so they show up in `git log` rather than in the diff):

- `Package.swift` — `.define("ENABLE_ARM_SHANI", .when(platforms: [.macOS, .iOS, .macCatalyst, .tvOS, .visionOS]))` in `kernelSettings`.
- `subtree.yaml` — `sha256_arm_shani.cpp` moved from the `bitcoind` source glob (where it compiled dead) to the `libbitcoinkernel` list, alongside its crypto siblings: added to the kernel `from:` list and to the `bitcoind` rule's `exclude:` list, which is how a move out of a wildcard glob is expressed. The extracted copy moved with `git mv` and the patch applied to it in place.
- `Sources/bitcoind/include/bitcoin-config.h`, `include/config/bitcoin-config.h` — deleted: stale autotools-generated headers from the v26 era, superseded by `bitcoin-build-config.h` when upstream moved to CMake (upstream itself deleted both paths in #30937). Zero references by any include form; they were also the tree's last stray `#define ENABLE_ARM_SHANI 1`, which this change makes deliberate and single-sourced.
- `Sources/{Bitcoin,BitcoinKernel}/PrivacyInfo.xcprivacy` — comment updated: `sha256.cpp`'s new `sysctlbyname("hw.optional.arm.FEAT_SHA256")` call joins the existing `sysctl` coverage under `SystemBootTime`/`35F9.1`.
- `Tests/SHA256DispatchProbe` — a test-only C++ target calling `SHA256AutoDetect()` directly; `SHA256DispatchTests.swift` asserts the returned implementation name per-arch, turning a silently-scalar build into a loud test failure.

**x86 deferral, recorded.** `ENABLE_SSE41`/`ENABLE_AVX2`/`ENABLE_X86_SHANI` stay off, deliberately: upstream enables them the same way (per-file `-msse4.1`/`-mavx2`/`-msha`), but a flat build cannot raise the ISA baseline target-wide without emitting illegal instructions on CPUs below it, and a correct flat-build port needs function-level `__attribute__((target))` surgery on three more vendored files — disproportionate to the remaining life of Intel macOS (26 is the final Intel release; our deployment floor gets security updates for roughly one more year). Note the baseline is not fully scalar: `compat/cpuid.h` self-defines `HAVE_GETCPUID` on x86, so the already-extracted `sha256_sse4.cpp` has silently provided the `sse4(1way)` path on Intel all along. Revisit only if a flat-build-safe formulation appears.

Verification on this branch: arm64 object for `sha256_arm_shani.cpp` contains `sha256h`/`sha256h2` instructions; `nm` shows the `sha256_arm_shani::Transform`/`sha256d64_arm_shani::Transform_2way` symbols defined in the arm64 slice only; `SHA256DispatchProbe` reports `arm_shani(1way;2way)` on Apple Silicon and `sse4(1way)` on x86_64 (the pre-existing SSE4 one-way path).
