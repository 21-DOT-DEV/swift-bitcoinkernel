// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Bitcoin",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "Bitcoin", targets: ["Bitcoin"]),
        .library(name: "BitcoinKernel", targets: ["BitcoinKernel"]),
    ],
    traits: [
        .trait(name: "wallet")
    ],
    dependencies: [
        .package(url: "https://github.com/21-DOT-DEV/swift-boost", branch: "pruned-umbrella-1.90.0"),
        .package(url: "https://github.com/21-DOT-DEV/swift-event", exact: "0.2.1"),
    ] + Package.Dependency.developmentDependencies,
    targets: [

        .target(
            name: "Bitcoin",
            dependencies: ["bitcoind"],
            swiftSettings: SwiftSetting.bitcoinSettings
        ),
        .target(
            name: "BitcoinKernel",
            dependencies: ["libbitcoinkernel"]
        ),

        // MARK: - Bitcoin Core

        .target(
            name: "libbitcoinkernel",
            dependencies: Target.Dependency.kernelDeps,
            exclude: ["src/crypto/ctaes/ctaes.c"],
            publicHeadersPath: "include",
            cxxSettings: CXXSetting.kernelSettings
        ),
        .target(
            name: "bitcoind",
            dependencies: Target.Dependency.bitcoinDeps,
            exclude: ["src/bridge/README.md"],
            publicHeadersPath: "include",
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
            publicHeadersPath: "include",
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
        .testTarget(
            name: "BitcoinKernelTests",
            dependencies: ["BitcoinKernel"]
        ),
    ],
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
            .package(url: "https://github.com/21-DOT-DEV/swift-plugin-tuist.git", exact: "4.20.0"),
            .package(url: "https://github.com/21-DOT-DEV/swift-plugin-subtree.git", exact: "0.0.15"),
            .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.5.0"),
        ]
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
        .headerSearchPath("src"),
        .headerSearchPath("src/univalue/include"),
        // Disable `multi_index_container`'s serialization member templates
        // — we never call them in the swift-bitcoin subset, and skipping
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
        ]
}
