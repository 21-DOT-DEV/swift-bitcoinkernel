# Compile the network-interface file on iPhone-family SDKs

`src/common/netif.cpp` looks up the system's default network gateway. Its Apple branch includes `<net/route.h>`, a header only the Mac SDK ships — the iPhone, TV, watch, and headset SDKs all lack it, so the file fails to compile for those targets. The fix compiles the route-table code only where its header exists, using `__has_include` — the same guard `src/randomenv.cpp` already uses for system headers. On Apple platforms without the header, the lookup falls through to the file's existing unsupported-platform answer (`std::nullopt`, "no gateway found"), the same as on any OS the file doesn't know.

| | |
|---|---|
| **Status** | Applied here; not yet filed upstream. Still needed on master: the bare `__APPLE__` guards remain (re-verified 2026-07-18). The guard sites moved to `netif.cpp:21,220` on master after #35659 dropped the FreeBSD workaround, so expect context drift at rebase. |
| **Touches** | `src/common/netif.cpp` |
| **Depends on** | Nothing. |
| **File as** | Direct pull request — step 1 of [the pipeline](../UPSTREAMING.md#the-pipeline): smallest change, files first, builds the track record. No separate issue: an issue would frame this as a platform-support question, and that framing has been closed twice (#21208 as duplicate of #11720; #11720 as "Superceded by kernel"). The PR must be judged as an inert two-line diff — the same one-line change at both guard sites. |
| **PR title** | `net: use __has_include to narrow __APPLE__ guards` |
| **Cite** | [#27587](https://github.com/bitcoin/bitcoin/issues/27587) — the kernel-library tracker, as context that building Bitcoin Core pieces for Apple platforms is a live, supported direction. Nothing else needed in the description. |

## The change

```diff
diff --git a/src/common/netif.cpp b/src/common/netif.cpp
--- a/src/common/netif.cpp
+++ b/src/common/netif.cpp
@@ -24,7 +24,7 @@
 #endif
 #elif defined(WIN32)
 #include <iphlpapi.h>
-#elif defined(__APPLE__)
+#elif defined(__APPLE__) && __has_include(<net/route.h>)
 #include <net/route.h>
 #include <sys/sysctl.h>
 #endif
@@ -226,7 +226,7 @@ std::optional<CNetAddr> QueryDefaultGatewayImpl(sa_family_t family)
     return std::nullopt;
 }
 
-#elif defined(__APPLE__)
+#elif defined(__APPLE__) && __has_include(<net/route.h>)
 
 #define ROUNDUP32(a) \
     ((a) > 0 ? (1 + (((a) - 1) | (sizeof(uint32_t) - 1))) : sizeof(uint32_t))
```

This is the `.patch` artifact verbatim; it applies cleanly to the vendored v31.0 tree (checked 2026-07-18; the pristine guard sites sit at `src/common/netif.cpp:27,229` there). Rebase onto current `master` before opening the PR.

## Writing the PR

The description is settled (filer-drafted, 2026-07-18). File it as written; the same text serves as the commit body under the title:

> The `__APPLE__` macro is defined on all Apple platforms, but only the macOS SDK ships `<net/route.h>`. Use `__has_include(<net/route.h>)` to compile the route-table code only where its header exists, the same idiom `randomenv.cpp` and `util/threadnames.cpp` use for system headers, so unsupported platforms use the existing dummy implementation (`return std::nullopt`).
>
> No behavior change on any currently built platform; no CI changes are requested.

The rules it follows, for any future revision:

- Mechanical claims only; no compile-failure narrative; platforms never named individually. This is the style of the file's own most recent hygiene PR (#35658, a maintainer's, merged 2026-07-06, which kept its unsupported platform — illumos — to a reference link). "Unsupported platforms" is normal merged-PR vocabulary (#33435).
- Imperative mood ("Use …"); no "this change aims to"; no "leverage". Commit-message conventions apply because the description doubles as the commit body.
- Nothing pre-argued: no `TARGET_OS_OSX`, no `HAVE_NET_ROUTE_H`, no `MAC_OSX` history, no precedent PR numbers. Merged compat PRs run one to four sentences; every answer lives in the next section, for replies.
- Every claim verifiable against master in seconds: the two facts, the two cited files, the dummy implementation, the impact line.

## If reviewers push back (for replies, in your own words — not the description)

Facts held ready. Bitcoin Core's AI policy requires replies to be human-written, so these are arguments to make, not text to paste.

**"This guard shape is odd/novel."** The file was founded on exactly this shape: #30043 shipped `netif.cpp` with an availability gate inside a platform branch (`#if __FreeBSD_version >= 1400000` inside `#elif defined(__FreeBSD__)`), a compound implementation guard (`defined(__FreeBSD__) && __FreeBSD_version >= 1400000`), and fall-through to the dummy implementation — because FreeBSD variants' capabilities diverged. #35659 later removed that gate only because pre-14 FreeBSD support ended entirely; the pattern retired with its subject, it was not rejected. Apple is the second platform to need the file's founding design, with a header test instead of a version test. One structural difference, if pressed: FreeBSD's include site had to nest (`__FreeBSD_version` does not exist until `<osreldate.h>` is included, so the branch must be entered before the test); `__has_include` has no prerequisite, so this patch uses the identical compound at both sites.

**"Why bother? Nothing we build is affected."** The bare `__APPLE__` guard selects code that cannot compile where the header does not exist, so the file fails to compile against Apple's non-macOS SDKs. Downstream projects embedding Bitcoin Core build against those SDKs continuously (our Apple CI exercises the path on every commit), and per-platform compile receipts exist for both the patched and the pristine file (see Notes).

**"Why not `TARGET_OS_OSX` from `<TargetConditionals.h>`?"** It works — an earlier draft of this patch used it and compiled on all four Apple platforms (receipts below) — but it would be the first use of `TargetConditionals` anywhere in the codebase, while `__has_include` on system headers is already established (`src/randomenv.cpp:46-52`, `src/util/threadnames.cpp:17`). The `__has_include` form also needs no new include line and tests the exact condition that fails.

**"Why not a `HAVE_NET_ROUTE_H` configure check, like `HAVE_IFADDRS` in this same file?"** Concede the nearest precedent's difference first: #32405 converted existing configure probes to `__has_include`; it did not convert a platform guard, and no PR has performed exactly this transformation. Then the composition argument: both halves are established practice — `__has_include` as the header-availability test (#32405 deleted introspection probes in its favor; `ab878a7e` removed two more header probes outright), and platform-and-availability compound guards (`fs_helpers.cpp:114`'s `defined(__APPLE__) && defined(F_FULLFSYNC)`; the `MSG_NOSIGNAL`/`MSG_DONTWAIT` family, #9921). The composition is new only because `__APPLE__` is the sole platform macro spanning operating systems whose SDKs diverge. A new probe would also grow the diff into `introspection.cmake` and the config template, and `HAVE_IFADDRS` earns its probe by gating a portable fallback shared across many OSes — this block is a single-platform mechanism behind one header.

**"Is `<sys/sysctl.h>` also missing?"** No — only `<net/route.h>` is absent from the non-macOS Apple SDKs; `<sys/sysctl.h>` ships on all of them (header table below). It stays inside the guard because the guarded block is its only consumer; hoisting it would add a dead include on every non-macOS Apple platform, which the include-what-you-use checks treat as errors in covered directories.

**If the `MAC_OSX` history comes up** (#29834 → #29450 removed the custom macOS macro in 2025): this change adds no macOS-identity macro at all, so that cleanup is untouched — the guard asks about the header, not the OS.

## Notes

Header availability, verified against the installed Xcode 27.0 SDKs on 2026-07-02 (see the [CMake memo](cmake-ios-library-build.md) for the probe commands):

| Header | macOS | iOS | tvOS | watchOS | visionOS |
|--------|-------|-----|------|---------|----------|
| `<net/route.h>` | Yes | No | No | No | No |
| `<sys/sysctl.h>` | Yes | Yes | Yes | Yes | Yes |

Filing-time context (checked 2026-07-18): `netif.cpp` and `src/common/` are under an active maintenance wave — #35658 (merged 2026-07-06) and #35659 (merged 2026-07-13) groomed the file, and #34995 (open) is bringing include-what-you-use enforcement to `src/common/`. Timing is favorable: the likely reviewers have the file paged in, and this patch's keep-headers-with-their-consumer discipline matches that effort. Watchpoint: if #34995 merges first, expect include shuffling — re-run `git apply --check` and rebase before filing.

Compile verification, 2026-07-18, for the `__has_include` form. The whole file was compiled per platform (not just header probes), with pristine v31 as the control:

| Translation unit | macOS | iOS | tvOS | visionOS |
|---|---|---|---|---|
| Patched, as applied (compound guard at both sites) | Compiles | Compiles | Compiles | Compiles |
| Pristine v31 | Compiles | Fails | Fails | Fails |
| Variant: `<sys/sysctl.h>` hoisted above the guard | Compiles | Compiles | Compiles | Compiles |
| Earlier `TARGET_OS_OSX` draft (2026-07-17) | Compiles | Compiles | Compiles | Compiles |

Every pristine failure is identical: `netif.cpp:28: fatal error: 'net/route.h' file not found`. Command shape: `xcrun --sdk <sdk> clang++ -std=c++20 -fsyntax-only -target <triple> -ISources/bitcoind/include -ISources/libbitcoinkernel/src Sources/bitcoind/src/common/netif.cpp`.

The hoisted variant works everywhere but stays rejected: the guarded block is the only consumer of both headers, so hoisting `<sys/sysctl.h>` adds a dead include on every non-Mac Apple platform, and Bitcoin Core's CI runs include-what-you-use checks that treat violations in covered directories as errors. Both headers stay with their only consumer.

Caveats: compile-level verification only — nothing was linked or run on tvOS/visionOS; the `Bitcoin` product remains unbuildable for tvOS for the unrelated child-process prohibition ([memo](tvos-execvp-feasibility.md)); CI exercises macOS and iOS only.
