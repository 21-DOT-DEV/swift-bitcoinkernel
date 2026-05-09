# swift-boost: Linux Module Compilation Fix

**Date**: 2026-05-08
**Status**: Workaround applied (see Solution)
**Repo**: https://github.com/21-DOT-DEV/swift-boost

## Problem

swift-boost provides each Boost module as a header-only SPM target with an empty `.cpp` source file for automatic module generation. On macOS, Clang builds these modules implicitly via `-fmodules`. On Linux (Docker `swift:6.3`), `-fno-implicit-modules` is the default, and the pre-built `.pcm` files are not generated during dependency resolution.

When a consumer like swift-bitcoin's vendored Bitcoin Core C++ code does:

```cpp
#include <boost/multi_index/hashed_index.hpp>
```

Clang attempts to use the `multi_index` module but fails:

```
fatal error: module 'multi_index' is needed but has not been provided,
and implicit use of module files is disabled
```

This affects all 37 boost modules transitively included by Bitcoin Core.

## Solution

### Current workaround (swift-bitcoin)

Add `-Xcc -fimplicit-modules` to the `swift build` invocation in the Dockerfile:

```dockerfile
RUN swift build -Xcc -fimplicit-modules
```

This tells Clang to build missing modules on-the-fly, matching macOS behavior. The flag is scoped to the Docker build only — it does not affect Package.swift or downstream consumers.

### Long-term fix (swift-boost)

Add explicit `module.modulemap` files to each boost target. This eliminates the need for implicit module building entirely:

```
Sources/multi_index/include/module.modulemap:
module multi_index {
    umbrella "boost/multi_index"
    export *
}
```

A generation script for all 37 modules:

```bash
for dir in Sources/*/; do
  name=$(basename "$dir")
  cat > "$dir/include/module.modulemap" <<EOF
module $name {
    umbrella "boost/$name"
    export *
}
EOF
done
```

With explicit module maps, SPM builds the `.pcm` files during dependency resolution, and `-fimplicit-modules` is no longer needed.

## Related

- `inter-target-deps.md` — addresses the flat target dependency issue in swift-boost
- The module map fix can be applied independently of the inter-target dependency fix