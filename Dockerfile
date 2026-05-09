FROM swift:6.3
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git pkg-config libsqlite3-dev
WORKDIR /workspace
COPY . .
RUN swift --version

# Boost-on-Linux workaround: SwiftPM auto-generates per-target Clang module
# maps for swift-boost, but Boost's preprocessor metaprogramming
# (BOOST_PP_FILENAME_*, etc.) is fundamentally incompatible with Clang
# module compilation in isolation. On Linux, -fno-implicit-modules is the
# default, which surfaces as "module 'multi_index' is needed but has not
# been provided" because Clang refuses to build the module on demand.
# Swift's C++ interop forces -fmodules, so -fno-modules is not an option.
#
# Workaround: SwiftPM honors a pre-existing module.modulemap in a target's
# publicHeadersPath instead of auto-generating one. We write a stub map
# per affected target containing `requires !cplusplus` — a feature name
# defined by the Clang Modules spec, inverted so it is never satisfied in
# a Swift/C++ build. Clang registers the module name but skips compiling
# it; header lookups fall through to textual `#include` semantics via the
# normal `-I` paths already on the search path.
#
# The same approach applies to our local vendored C/C++ targets that ship
# without a curated modulemap (`secp256k1`, `crc32c`, `leveldb`,
# `minisketch`); they hit the identical "module needed but not provided"
# wall on Linux for the same reason.
#
# Proper long-term fix: have swift-boost ship its own modulemaps with
# explicit `textual header` declarations, and curate one for each
# vendored C target here. Tracked in
# patches/swift-boost/linux-module-compilation.md.
RUN swift package resolve && \
    for dir in .build/checkouts/*/Sources/*/include \
               Sources/secp256k1/include \
               Sources/crc32c/include \
               Sources/leveldb/include \
               Sources/minisketch/include; do \
        [ -d "$dir" ] || continue; \
        mod=$(basename "$(dirname "$dir")"); \
        printf 'module %s {\n    requires !cplusplus\n    export *\n}\n' "$mod" > "$dir/module.modulemap"; \
    done && \
    : "swift-event ships its libevent fork configured to use the bundled" && \
    : "arc4random.c on Linux. That worked on glibc <2.36, but glibc 2.36+" && \
    : "(Ubuntu 22.10 onward) added arc4random_buf to <stdlib.h>, which" && \
    : "collides with libevent's bundled 'static arc4random_buf' definition." && \
    : "Enable libevent's HAVE_ARC4RANDOM* gates so it links the system" && \
    : "implementation and skips compiling the bundled fallback." && \
    sed -i \
        -e 's|^#undef EVENT__HAVE_ARC4RANDOM$|#define EVENT__HAVE_ARC4RANDOM 1|' \
        -e 's|^#undef EVENT__HAVE_ARC4RANDOM_BUF$|#define EVENT__HAVE_ARC4RANDOM_BUF 1|' \
        .build/checkouts/swift-event/Sources/libevent/include/event2/event-config.h && \
    swift build
RUN swift test
RUN swift test --traits wallet
CMD ["swift", "test"]
