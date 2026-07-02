# CMake iOS library build — verification memo

**Date**: 2026-07-02
**Status**: Verification record, not an applied patch (like [`tvos-execvp-feasibility.md`](tvos-execvp-feasibility.md))
**Tree verified**: `Vendor/bitcoin` (pristine upstream v31.0; no `patches/` applied — confirmed by checking `src/common/netif.cpp` has no `TARGET_OS_OSX`, `src/rpc/server.cpp` retains both `once_flag`s, `src/compat/compat.h` has no `#ifndef` guard, `src/init.cpp` has no resets)
**Host**: macOS 15 (Darwin 25.5.0), Xcode 27.0 (iOS SDK 27.0), CMake 4.3.4

## What this proves

Pristine upstream Bitcoin Core v31 configures **and builds** `libbitcoinkernel` for iOS device and simulator with stock CMake. No source patches, no `depends`, no toolchain file. Output per platform: static `libbitcoinkernel.a`, arm64, 130 object files, plus `libbitcoinkernel.pc`.

Two consequences for this repo:

1. The patches in this directory are not what makes the kernel library possible on iOS. `src/common/netif.cpp` (the one iOS-SDK-incompatible source) is not part of the kernel library target at all (`ar -t` on the built archive: no `netif.o`). The patches earn their keep elsewhere: the in-process lifecycle set serves the embedded-`bitcoind` product, and the netif guard fixes daemon-side sources.
2. The committed `bitcoin-build-config.h` stand-ins can be checked against what CMake actually generates per platform, instead of being asserted by hand. Results below.

## Invocations

Boost first: upstream requires `find_package(Boost 1.74.0 REQUIRED CONFIG)` but only consumes headers (`Boost::headers`, multi_index for the mempool). The pinned [swift-boost](https://github.com/21-DOT-DEV/swift-boost) checkout has no CMake package config, so a two-file shim points CONFIG mode at its per-module include roots:

```sh
BOOST_SRC="$(pwd)/.build/checkouts/swift-boost/Sources"
INCS=$(ls -d "$BOOST_SRC"/*/include | tr '\n' ';' | sed 's/;$//')
mkdir -p /tmp/boost-shim
cat > /tmp/boost-shim/BoostConfigVersion.cmake <<'EOF'
set(PACKAGE_VERSION "1.90.0")
if(PACKAGE_FIND_VERSION VERSION_LESS_EQUAL PACKAGE_VERSION)
  set(PACKAGE_VERSION_COMPATIBLE TRUE)
else()
  set(PACKAGE_VERSION_COMPATIBLE FALSE)
endif()
EOF
cat > /tmp/boost-shim/BoostConfig.cmake <<EOF
if(NOT TARGET Boost::headers)
  add_library(Boost::headers INTERFACE IMPORTED)
  set_target_properties(Boost::headers PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "$INCS")
endif()
set(Boost_FOUND TRUE)
EOF
```

Configure and build (device; simulator swaps `-DCMAKE_OSX_SYSROOT=iphonesimulator`; the macOS baseline drops the three cross-compilation cache entries and uses `-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0`):

```sh
cmake -S Vendor/bitcoin -B build-ios-device \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
  -DBUILD_BITCOIN_BIN=OFF -DBUILD_DAEMON=OFF -DBUILD_CLI=OFF \
  -DBUILD_TESTS=OFF -DBUILD_TX=OFF -DBUILD_UTIL=OFF \
  -DBUILD_WALLET_TOOL=OFF -DENABLE_WALLET=OFF \
  -DENABLE_IPC=OFF -DENABLE_EXTERNAL_SIGNER=OFF \
  -DBUILD_KERNEL_LIB=ON -DBUILD_KERNEL_TEST=OFF \
  -DWITH_CCACHE=OFF \
  -DBoost_DIR=/tmp/boost-shim
cmake --build build-ios-device --target bitcoinkernel -j8
```

`-DENABLE_IPC=OFF` is deliberate: multiprocess/IPC ([#28722](https://github.com/bitcoin/bitcoin/issues/28722)) is additive upstream but defaults ON on Unix, pulling in the Cap'n Proto toolchain and the libmultiprocess subtree, and it has no application here — iOS apps cannot spawn helper processes.

Configure summary reports `Cross compiling ... TRUE, for iOS`. Both iOS configures produce byte-identical `src/bitcoin-build-config.h` (device == simulator).

This converges with [Sjors/kernel-i-node](https://github.com/Sjors/kernel-i-node) (announced on [#27587](https://github.com/bitcoin/bitcoin/issues/27587), 2026-03-14), whose `scripts/build-libbitcoinkernel.sh` drives the same flags against upstream master — `-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos|iphonesimulator -DCMAKE_OSX_ARCHITECTURES=arm64 -DBUILD_KERNEL_LIB=ON` with everything else off — differing only in `-DBUILD_SHARED_LIBS=ON` (embeds a `.dylib` and codesigns it from an Xcode phase) and Homebrew boost. Two independent reproductions, v31 and master.

## Generated vs. committed `bitcoin-build-config.h`

Comparison of CMake's generated header per platform against the committed stand-ins (`Sources/libbitcoinkernel/src/bitcoin-build-config.h` and `Sources/bitcoind/include/bitcoin-build-config.h`, which are identical except for `BITCOINKERNEL_BUILD`).

Validated — the hand-maintained guards match real introspection:

| Macro | Generated macOS | Generated iOS (dev = sim) | Committed | Verdict |
|---|---|---|---|---|
| `HAVE_GETENTROPY_RAND` | `1` | absent | `TARGET_OS_OSX`-gated | Matches. `sys/random.h` confirmed absent from the iPhoneOS 27.0 SDK, exactly as the committed comment states. |
| `HAVE_SYSTEM` | `1` | absent | `TARGET_OS_OSX`-gated | Matches (`std::system` unavailable on iOS). |
| `HAVE_SYSCTL` | `1` | `1` | `__APPLE__`-gated | Matches (`sys/sysctl.h` ships on every Apple SDK; see header table below). |
| `HAVE_DECL_FORK`, `HAVE_DECL_SETSID`, `HAVE_O_CLOEXEC`, `HAVE_SOCKADDR_UN` | `1` | `1` | `1` | Match. |
| `HAVE_FDATASYNC`, `STRERROR_R_CHAR_P` | absent | absent | undef | Match. |
| `CLIENT_*`, `COPYRIGHT_*` | — | — | — | Match (v31.0, year 2026). |

Divergences — recorded here, deliberately **not** changed in this pass:

| Macro | Generated | Committed | Notes |
|---|---|---|---|
| `HAVE_IFADDRS` | `1` on macOS **and** iOS | absent from both committed headers | Consumers: `src/randomenv.cpp` (a `getifaddrs` entropy input, linked into the kernel library too) and `src/common/netif.cpp`. SPM builds currently compile these paths out where CMake builds include them. Functional divergence with fallbacks, not a correctness bug; needs a decision. |
| `HAVE_DECL_PIPE2` | `0` on macOS, `1` on iOS (SDK 27.0) | `0` | The iOS 27 SDK now declares `pipe2`; macOS still doesn't. Caveat before "fixing": CMake's `try_compile` probes do not enforce availability attributes, so a declaration in the SDK does not guarantee availability at the package's iOS 18 deployment target. The committed `0` is the conservative, deployment-target-safe value. |

The second row is the general lesson: generated headers reflect the *SDK* under the configure's min-version flags, hand guards encode *deployment-target* decisions. Regeneration is a check, not a replacement.

## Apple SDK header facts (verified against installed SDKs, Xcode 27.0)

| Header | macosx | iphoneos | appletvos | watchos | xros |
|---|---|---|---|---|---|
| `<net/route.h>` | present | absent | absent | absent | absent |
| `<sys/sysctl.h>` | present | present | present | present | present |
| `<sys/random.h>` | present | absent | — | — | — |

The one header `src/common/netif.cpp` needs and cannot get on non-macOS Apple platforms is `<net/route.h>` (route-message structs). `sysctl()` itself is available everywhere; earlier drafts of the netif patch overstated this as "`<net/route.h>` and `<sys/sysctl.h>` unavailable," which [`ios-netif-guard.md`](ios-netif-guard.md) now corrects.

## Historical context, briefly

The [#11720](https://github.com/bitcoin/bitcoin/issues/11720) lineage tried to cross-compile the *daemon*: bare configure (2017), then `depends` with an overloaded `aarch64-apple-darwin19` triplet ([#12557](https://github.com/bitcoin/bitcoin/pull/12557)), then fanquake's since-deleted `arm64-apple-ios` depends branch (2022). Each stalled on triplet conflation with macOS-arm64, per-rebase breakage, and no way to run the result. Sjors' 2022-09-06 pivot — build the kernel *library* and let the app own networking and storage — became the close ("Superceded by kernel", 2023-04-27). Master today has no iOS awareness at all (no `depends/hosts/ios.mk`, zero `TARGET_OS_IPHONE` hits) and, as shown above, needs none for the kernel library: platform logic is exact-match `"Darwin"` blocks that an iOS configure simply skips.

What an upstream contribution could still add, in ascending effort:

1. **Nothing** — the configure path already works; arguably the correct resting state.
2. **A build doc** for the kernel-library-on-iOS invocation, citing kernel-i-node as the working example. Smallest honest artifact; listed as optional in [the pipeline](../UPSTREAMING.md#the-pipeline).
3. **A first-class `depends/hosts/ios.mk`** — mechanical from today's `darwin.mk` (`--target=arm64-apple-ios`, iPhoneOS sysroot, `-mios-version-min=…`, `-Wl,-platform_version,ios,MIN,SDKVER`, `ios_cmake_system_name=iOS`), but `depends` exists to build packages the kernel library doesn't need, so demand is unproven.

## Reproduce

```sh
swift package resolve   # materializes .build/checkouts/swift-boost
# then the shim + configure + build blocks above, from the repo root
lipo -info build-ios-device/lib/libbitcoinkernel.a   # arm64
```
