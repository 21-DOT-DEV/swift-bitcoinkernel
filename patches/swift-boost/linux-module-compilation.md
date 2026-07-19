# Linux module compilation (resolved)

| | |
|---|---|
| **Status** | Resolved upstream, 2026-05-11 — swift-boost's `pruned-umbrella-1.90.0` tag ships the fix and this package pins that tag. Kept as a historical note. |
| **Repo** | https://github.com/21-DOT-DEV/swift-boost |

The problem, for the record: Boost's headers are not designed to compile as standalone Clang modules — they expect macros defined by whoever includes them, and module compilation provides no such context. On Linux, Swift's C++ interop mode compiled them as modules anyway and every build failed with "module 'multi_index' is needed but has not been provided". The upstream fix is `requires !cplusplus` module-map stubs in each target: the module owns no headers, so C++ code keeps including Boost textually through ordinary include paths. This package uses the same stub pattern for its own C/C++ targets — see [Custom build files](../README.md#custom-build-files-not-patches). The old Dockerfile workaround (copying headers into a module-free include directory) is retired.
