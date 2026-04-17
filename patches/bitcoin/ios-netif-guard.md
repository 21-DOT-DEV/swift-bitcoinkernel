# Bitcoin Core Upstream PR: iOS Build Compatibility for `netif.cpp`

Prepared draft for contributing `TARGET_OS_OSX` guards to Bitcoin Core's `src/common/netif.cpp`.

## PR Title

```
net: guard macOS-only route headers for iOS build compatibility
```

## PR Description

```markdown
Narrow `__APPLE__` preprocessor guards to `__APPLE__ && TARGET_OS_OSX` in
`src/common/netif.cpp`, so the file compiles on iOS/tvOS/watchOS targets.

**Motivation:**

`<net/route.h>` and `<sys/sysctl.h>` are not available in the iOS SDK (or other
non-macOS Apple platforms). When building Bitcoin Core as an embedded library for
iOS — an increasingly relevant use case as mobile Bitcoin apps mature — the
existing `__APPLE__` guards cause compilation failures because they include iOS,
which is an Apple platform but does not ship these route-socket headers.

The macOS-specific `QueryDefaultGatewayImpl()` function uses `sysctl()` with
`CTL_NET/PF_ROUTE/NET_RT_FLAGS` to read the kernel routing table — an API
exclusive to macOS. On iOS, the function gracefully falls through to the final
`return std::nullopt` fallback, which is the correct behavior (iOS apps have no
use for raw route-table queries).

This aligns with Bitcoin Core's cross-platform goals and the ongoing
libbitcoinkernel library extraction (#24303), making it easier for external
projects to build Bitcoin Core components on Apple's non-macOS platforms.

**Change:**

Two locations in `src/common/netif.cpp`:

1. Include block: narrow `__APPLE__` include guard to `__APPLE__` + `TARGET_OS_OSX`
2. Implementation block: narrow `__APPLE__` platform check to `__APPLE__ && TARGET_OS_OSX`

**Impact:**

- Zero behavior change on macOS, Linux, Windows, or FreeBSD
- On iOS/tvOS/watchOS: `QueryDefaultGatewayImpl()` returns `std::nullopt`
  (same as any unsupported platform), instead of failing to compile
- No test changes required — no existing CI targets iOS
- Does not affect consensus code
```

## Commit Message

```
net: guard macOS-only route headers for iOS build compatibility

Narrow __APPLE__ preprocessor guards in src/common/netif.cpp to
__APPLE__ && TARGET_OS_OSX, so the file compiles when targeting iOS
and other non-macOS Apple platforms.

<net/route.h> and <sys/sysctl.h> are not available in the iOS SDK.
The macOS-specific QueryDefaultGatewayImpl() route-table code is not
applicable on iOS, where the function correctly falls through to the
std::nullopt return.

This follows the standard Apple pattern of using TargetConditionals.h
to distinguish macOS from other Apple platforms, and changes no
behavior on any currently supported platform.
```

## File Changed

**`src/common/netif.cpp`** — 4 lines changed (2 include guard, 1 platform check, 1 new include)

### Diff (against current `master`)

```diff
diff --git a/src/common/netif.cpp b/src/common/netif.cpp
--- a/src/common/netif.cpp
+++ b/src/common/netif.cpp
@@ -24,8 +24,11 @@
 #elif defined(WIN32)
 #include <iphlpapi.h>
 #elif defined(__APPLE__)
-#include <net/route.h>
-#include <sys/sysctl.h>
+#include <TargetConditionals.h>
+#if TARGET_OS_OSX
+#include <net/route.h>
+#include <sys/sysctl.h>
+#endif
 #endif

@@ -229,7 +232,7 @@
     return std::nullopt;
 }

-#elif defined(__APPLE__)
+#elif defined(__APPLE__) && TARGET_OS_OSX

 #define ROUNDUP32(a) \
```

## Bitcoin Core PR Process Checklist

Per [CONTRIBUTING.md](https://github.com/bitcoin/bitcoin/blob/master/CONTRIBUTING.md):

- [ ] Fork `bitcoin/bitcoin` and create a branch from `master`
- [ ] Rebase the change onto current `master`
- [ ] Verify the diff applies cleanly to current `master`'s `netif.cpp`
- [ ] Run the existing test suite: `ctest --test-dir build` (no new tests needed — no behavior change)
- [ ] PR title uses area prefix: `net:` (matches module area)
- [ ] Commit message follows project conventions (imperative mood, no `@` mentions)
- [ ] No `@` mentions in PR description (use follow-up comments for pings)
- [ ] Consider pinging reviewers who last touched this code (use `git blame src/common/netif.cpp`)

## Context & Prior Art

### How `netif.cpp` works today

- Introduced in Bitcoin Core to provide cross-platform default gateway detection
- Platform branches: Linux (`rtnetlink`), FreeBSD (`netlink`), Windows (`iphlpapi`), macOS (`sysctl` + route socket)
- The `__APPLE__` branch is currently the only platform check that doesn't distinguish between OS variants

### Apple platform header availability

| Header | macOS | iOS | tvOS | watchOS |
|--------|-------|-----|------|---------|
| `<net/route.h>` | Yes | No | No | No |
| `<sys/sysctl.h>` | Yes | Deprecated | No | No |
| `<TargetConditionals.h>` | Yes | Yes | Yes | Yes |

### `TARGET_OS_OSX` usage pattern

`TARGET_OS_OSX` (from `<TargetConditionals.h>`) is the standard Apple mechanism
for distinguishing macOS from other Apple platforms. It evaluates to `1` on macOS
and `0` on iOS/tvOS/watchOS/visionOS. This pattern is widely used in Apple's own
frameworks and third-party cross-platform libraries.

### Related PRs & Issues

| PR/Issue | Title | Relevance |
|---|---|---|
| [#24303](https://github.com/bitcoin/bitcoin/issues/24303) | `The libbitcoinkernel Project` | Library extraction — makes Bitcoin Core embeddable in external apps |
| [#11720](https://github.com/bitcoin/bitcoin/issues/11720) | `iOS Deployment Target for RPC` | Prior discussion of iOS as a target platform |
| [#27587](https://github.com/bitcoin/bitcoin/issues/27587) | `Bitcoin Kernel Library Project Tracking` | Ongoing kernel library work |

## Labels to Request

- `P2P` — affects network interface detection
- `Build system` — platform compatibility
