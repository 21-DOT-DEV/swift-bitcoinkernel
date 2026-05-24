# swift-boost: Linux Module Compilation Fix

**Date**: 2026-05-08 (initial); 2026-05-11 (resolved upstream)
**Status**: ✅ Resolved — `pruned-umbrella-1.90.0` ships `requires !cplusplus` modulemaps in each target's `include/` directory. swift-bitcoinkernel pins that tag and no longer injects module maps for swift-boost paths. The Linux Dockerfile workaround has been retired entirely; the equivalent stubs for swift-bitcoinkernel's local C/C++ targets are now committed in-tree (see [Non-patch custom files](../README.md#non-patch-custom-files)).
**Repo**: https://github.com/21-DOT-DEV/swift-boost

## Problem

swift-boost provides each Boost module as a header-only SPM target. SPM auto-generates Clang module maps for each target. On macOS, `-fmodules` allows implicit module building and compilation succeeds. On Linux (Docker `swift:6.3`), `-fno-implicit-modules` is the default, causing:

```
fatal error: module 'multi_index' is needed but has not been provided,
and implicit use of module files is disabled
```

This affects all 37 boost modules transitively included by Bitcoin Core.

## What doesn't work

| Approach | Result | Why |
|----------|--------|-----|
| `-Xcc -fimplicit-modules` | Fails | Boost headers use preprocessor metaprogramming (`# include BOOST_PP_FILENAME_4`) that breaks when compiled as Clang modules in isolation |
| `-Xcc -fno-modules` | Fails | C++ interop mode forces `-fmodules`, overriding user flags |
| `-Xcc -fno-implicit-module-maps` | Fails | Same override by C++ interop |
| Delete module maps before build | Fails | SPM re-generates them during `swift build` |
| Add explicit `-I` paths | Fails | Clang prefers module resolution over `-I` include paths |

## Root cause

Boost headers are NOT designed to be compiled as Clang modules. They rely on caller-defined macros (e.g., `BOOST_PP_FILENAME_4` must be set before including `forward4.hpp`). When Clang builds a module, it preprocesses all umbrella headers in isolation — no caller context, no pre-defined macros — and fails.

## Solution

### Long-term fix (swift-boost)

The module-based approach is fundamentally incompatible with Boost's preprocessor metaprogramming on Linux. Options:

**A) Textual headers** — mark all headers as `textual` in module maps so Clang skips module compilation and treats them as regular includes:

```
module multi_index {
    textual umbrella "boost/multi_index"
    export *
}
```

**B) Abandon modules** — restructure swift-boost as a single header-only target with traditional include paths, no module maps. This avoids the entire module compilation problem and matches how Boost is used in every other build system (CMake, Bazel, etc.).

Option B is simpler and more reliable. Boost is header-only; there's no benefit to compiling it as Clang modules.

### Current workaround (swift-bitcoinkernel Dockerfile)

Aggregate all boost headers into a module-free include directory after dependency resolution:

```dockerfile
RUN swift package resolve && \
    mkdir -p .build/boost-include/boost && \
    for dir in .build/checkouts/swift-boost/Sources/*/include/boost/*; do \
        cp -r "$dir" .build/boost-include/boost/; \
    done && \
    swift build -Xcc -I.build/boost-include
```

This bypasses the module system entirely for boost headers by providing them via a plain `-I` path with no module map.

## Related

- `inter-target-deps.md` — addresses the flat target dependency issue in swift-boost
- Both fixes should be applied together when restructuring swift-boost