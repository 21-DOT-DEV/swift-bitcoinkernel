// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "BitcoinKernel",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "Bitcoin", targets: ["Bitcoin"]),
        .library(name: "BitcoinKernel", targets: ["BitcoinKernel"]),
    ],
    traits: [
        .trait(name: "wallet")
    ],
    dependencies: [
        // Pinned to the pruned-umbrella-1.90.0 release commit. That tag name is not
        // SemVer, so it cannot be used with `exact:`; a revision pin is reproducible
        // and removes the (non-existent) branch reference.
        .package(url: "https://github.com/21-DOT-DEV/swift-boost", revision: "6d8c72c0f41a20ec47b25096e4c422ef34f67579"),
        .package(url: "https://github.com/21-DOT-DEV/swift-event", exact: "0.2.1"),
    ] + Package.Dependency.developmentDependencies,
    targets: [

        .target(
            name: "Bitcoin",
            dependencies: ["bitcoind"],
            exclude: Target.privacyManifestExclude,
            resources: Target.privacyManifestResources,
            swiftSettings: SwiftSetting.bitcoinSettings
        ),
        .target(
            name: "BitcoinKernel",
            dependencies: ["libbitcoinkernel"],
            exclude: Target.privacyManifestExclude,
            resources: Target.privacyManifestResources
        ),

        // MARK: - Bitcoin Core

        .target(
            name: "libbitcoinkernel",
            dependencies: Target.Dependency.kernelDeps,
            exclude: ["src/crypto/ctaes/ctaes.c"],
            cxxSettings: CXXSetting.kernelSettings
        ),
        .target(
            name: "bitcoind",
            dependencies: Target.Dependency.bitcoinDeps,
            exclude: ["src/bridge/README.md"],
            cxxSettings: CXXSetting.bitcoinSettings,
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),

        // MARK: - Vendored C/C++ Libraries

        .target(name: "crc32c"),
        .target(
            name: "leveldb",
            cxxSettings: [
                // See CXXSetting.shared: override the toolchain's Debug default of
                // libc++ DEBUG hardening (O(n) container-invariant checks) with FAST.
                .define("_LIBCPP_HARDENING_MODE", to: "_LIBCPP_HARDENING_MODE_FAST"),
                .define("LEVELDB_PLATFORM_POSIX", to: "1"),
                .define("LEVELDB_IS_BIG_ENDIAN", to: "0"),
                // `port_config.h` defaults assume Apple (HAVE_FULLFSYNC=1, HAVE_FDATASYNC=0).
                // The header guards each define with `#if !defined(...)`, so passing the
                // correct flags for Linux from the build is enough — no source patch needed.
                .define("HAVE_FDATASYNC", to: "1", .when(platforms: [.linux])),
                .define("HAVE_FULLFSYNC", to: "0", .when(platforms: [.linux])),
                .headerSearchPath("."),
            ]
        ),
        .target(name: "minisketch"),
        .target(
            name: "secp256k1",
            cSettings: [
                .define("ECMULT_GEN_PREC_BITS", to: "4"),
                .define("ECMULT_WINDOW_SIZE", to: "15"),
                .define("ENABLE_MODULE_ELLSWIFT"),
                .define("ENABLE_MODULE_EXTRAKEYS"),
                .define("ENABLE_MODULE_RECOVERY"),
                .define("ENABLE_MODULE_SCHNORRSIG"),
                .define("ENABLE_MODULE_MUSIG"),
            ]
        ),

        // MARK: - Tests

        .testTarget(
            name: "BitcoinTests",
            dependencies: ["Bitcoin"],
            resources: [.copy("Fixtures")],
            swiftSettings: SwiftSetting.bitcoinSettings
        ),
        // Test-only C++ probe reporting which SHA-256 implementation the
        // dispatcher selects at runtime. BitcoinKernelTests asserts on the
        // string directly instead of racing the kernel's once-per-process
        // selection log line.
        .target(
            name: "SHA256DispatchProbe",
            dependencies: ["libbitcoinkernel"],
            path: "Tests/SHA256DispatchProbe",
            cxxSettings: [
                .headerSearchPath("../../Sources/libbitcoinkernel/src"),
            ]
        ),
        .testTarget(
            name: "BitcoinKernelTests",
            dependencies: ["BitcoinKernel", "SHA256DispatchProbe"]
        ),
    ],
    // Matches the vendored secp256k1 C sources, which are written to C89.
    // SwiftPM applies one C standard to every C target in the package.
    cLanguageStandard: .c89,
    cxxLanguageStandard: .cxx20
)

// MARK: - Extensions

extension Package.Dependency {
    /// Development-only dependencies, excluded at tagged releases.
    ///
    /// When resolved at a tagged release (`Context.gitInformation?.currentTag != nil`),
    /// development tools (tuist, subtree, docc) are excluded so consumers aren't
    /// forced to download them. Runtime dependencies (`swift-boost`, `swift-event`)
    /// stay inline above and always resolve.
    static var developmentDependencies: [Package.Dependency] {
        guard Context.gitInformation?.currentTag == nil else { return [] }
        return [
            .package(url: "https://github.com/21-DOT-DEV/swift-plugin-tuist.git", exact: "4.195.11"),
            .package(url: "https://github.com/21-DOT-DEV/swift-plugin-subtree.git", exact: "0.0.15"),
            .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.5.0"),
        ]
    }
}

extension Target {
    /// Exclude and resource entries for a product target that ships a privacy
    /// manifest.
    ///
    /// `PrivacyInfo.xcprivacy` rides inside the product's resource bundle — the
    /// swift-crypto/swift-nio pattern — naming the required-reason system calls
    /// the vendored C++ code makes, so consumers' Xcode privacy reports
    /// attribute them to this SDK. The file is excluded off-Darwin, where an
    /// unhandled `.xcprivacy` would only warn; as upstream notes, that is still
    /// strictly better than adding the resource unconditionally.
    static var privacyManifestExclude: [String] {
        #if canImport(Darwin)
        []
        #else
        ["PrivacyInfo.xcprivacy"]
        #endif
    }

    /// See ``privacyManifestExclude``.
    static var privacyManifestResources: [PackageDescription.Resource] {
        #if canImport(Darwin)
        [.copy("PrivacyInfo.xcprivacy")]
        #else
        []
        #endif
    }
}

extension Target.Dependency {
    /// Dependencies for the libbitcoinkernel target.
    static let kernelDeps: [Self] = [
        .product(name: "boost", package: "swift-boost"),
        .target(name: "crc32c"),
        .target(name: "leveldb"),
        .target(name: "secp256k1"),
    ]

    /// Dependencies for the bitcoind target.
    static let bitcoinDeps: [Self] =
        kernelDeps + [
            .product(name: "libevent", package: "swift-event"),
            .target(name: "minisketch"),
            .target(name: "libbitcoinkernel"),
        ]
}

extension SwiftSetting {
    /// Swift settings for the Bitcoin target.
    ///
    /// - Note: Xcode does not resolve `.when(traits:)` conditions for Swift settings,
    ///   so Swift source files use `#if Xcode || ENABLE_WALLET` guards as a workaround.
    ///   Xcode automatically defines `Xcode` in all Swift compilations.
    static let bitcoinSettings: [Self] = [
        .interoperabilityMode(.Cxx),
        .define("ENABLE_WALLET", .when(traits: ["wallet"])),
    ]
}

extension CXXSetting {
    /// Shared C++ settings for all Bitcoin Core C++ targets.
    static let shared: [Self] = [
        // Override the toolchain's Debug default of
        // `_LIBCPP_HARDENING_MODE_DEBUG`, which compiles in libc++'s O(n)
        // container-invariant checks (`std::__tree_sub_invariant` on every
        // map/set insert/erase). During IBD Core's maps reach ~130k+ entries,
        // making those checks quadratic — one core pins at ~100%, validation
        // stalls holding `cs_main`, and every RPC poll times out (-1001). FAST
        // keeps the cheap O(1) checks (bounds, etc.) and drops the O(n) ones.
        // A target-level `-D` is emitted after the toolchain default, so it wins.
        .define("_LIBCPP_HARDENING_MODE", to: "_LIBCPP_HARDENING_MODE_FAST"),
        .headerSearchPath("src"),
        .headerSearchPath("src/univalue/include"),
        // Disable `multi_index_container`'s serialization member templates
        // — we never call them in the swift-bitcoinkernel subset, and skipping
        // their declaration keeps us decoupled from the standalone Boost
        // `serialization` module so it stays out of the dependency graph.
        .define("BOOST_MULTI_INDEX_DISABLE_SERIALIZATION"),
    ]

    /// C++ settings for the bitcoind target.
    static let bitcoinSettings: [Self] =
        shared + [
            .headerSearchPath("../libbitcoinkernel/src"),
            .headerSearchPath("../libbitcoinkernel/src/univalue/include"),
            .define("MAIN_FUNCTION", to: "int bitcoind_main(int argc, char* argv[])"),
            .define("G_TRANSLATION_FUN", to: "G_TRANSLATION_FUN_LOCAL"),
            .define("ENABLE_WALLET", to: "1", .when(traits: ["wallet"])),
            .define("HAVE_SYSTEM", to: "1", .when(platforms: [.linux])),
        ]

    /// C++ settings for the libbitcoinkernel target.
    static let kernelSettings: [Self] =
        shared + [
            .define("BITCOINKERNEL_BUILD", to: "1"),
            .define("HAVE_SYSTEM", to: "1", .when(platforms: [.linux])),
            // Turn on Bitcoin Core's ARMv8 SHA-2 path (upstream PR #24115).
            // Upstream's CMake gates it behind a per-file -march probe that
            // SwiftPM can't express, so the define is set once for every slice
            // and the vendored sources self-gate instead (see
            // patches/bitcoin/arm-shani-self-gate.patch): the dispatch block in
            // sha256.cpp needs an ARM target macro, the implementation file
            // needs __ARM_FEATURE_CRYPTO, and every non-ARM object compiles
            // empty. Apple-scoped: every Apple arm64 toolchain guarantees the
            // crypto baseline, and scoping avoids a dispatch-on/impl-off link
            // gap on crypto-less aarch64 (e.g. baseline Linux armv8-a).
            .define("ENABLE_ARM_SHANI", .when(platforms: [.macOS, .iOS, .macCatalyst, .tvOS, .visionOS])),
        ]
}
