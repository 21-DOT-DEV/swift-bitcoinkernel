// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Bitcoin",
    platforms: [
        .macOS(.v11),
        .iOS(.v14)
    ],
    products: [
        .library(name: "Bitcoin", targets: ["Bitcoin"]),
        .library(name: "BitcoinKernel", targets: ["BitcoinKernel"]),
        .library(name: "BitcoinWalletSupport", targets: ["BitcoinWalletSupport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/csjones/lefthook-plugin.git", exact: "1.6.15"),
        .package(url: "https://github.com/21-DOT-DEV/swift-boost", branch: "subtree-1.81.0"),
        .package(url: "https://github.com/21-DOT-DEV/swift-libevent", branch: "main"),
        .package(url: "https://github.com/21-DOT-DEV/swift-plugin-tuist.git", exact: "4.20.0"),
        .package(url: "https://github.com/21-DOT-DEV/swift-plugin-subtree.git", exact: "0.0.13"),
    ],
    targets: [
        .target(
            name: "bitcoind",
            dependencies: Target.Dependency.bitcoinDeps,
            publicHeadersPath: "include",
            cxxSettings: CXXSetting.bitcoinSettings
        ),
        .target(
            name: "walletsupport",
            dependencies: Target.Dependency.bitcoinDeps,
            publicHeadersPath: "include",
            cxxSettings: CXXSetting.bitcoinSettings,
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "Bitcoin",
            dependencies: ["bitcoind"],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
        .target(
            name: "BitcoinWalletSupport",
            dependencies: ["walletsupport"],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
        .target(name: "crc32c"),
        .target(
            name: "leveldb",
            cxxSettings: [
                .define("LEVELDB_PLATFORM_POSIX", to: "1"),
                .define("LEVELDB_IS_BIG_ENDIAN", to: "0"),
                .headerSearchPath("."),
            ]
        ),
        .target(name: "minisketch"),
        .target(
            name: "secp256k1",
            publicHeadersPath: "include",
            cSettings: [
                // Basic config values that are universal and require no dependencies.
                .define("ECMULT_GEN_PREC_BITS", to: "4"),
                .define("ECMULT_WINDOW_SIZE", to: "15"),
                // Enabling additional secp256k1 modules.
                .define("ENABLE_MODULE_ELLSWIFT"),
                .define("ENABLE_MODULE_EXTRAKEYS"),
                .define("ENABLE_MODULE_RECOVERY"),
                .define("ENABLE_MODULE_SCHNORRSIG"),
                .define("ENABLE_MODULE_MUSIG")
            ]
        ),
        .target(
            name: "libbitcoinkernel",
            dependencies: Target.Dependency.kernelDeps,
            exclude: ["src/crypto/ctaes/ctaes.c"],
            publicHeadersPath: "include",
            cxxSettings: CXXSetting.kernelSettings
        ),
        .target(
            name: "BitcoinKernel",
            dependencies: ["libbitcoinkernel"]
        ),
        .testTarget(
            name: "BitcoinTests",
            dependencies: [
                "Bitcoin",
                "BitcoinKernel",
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
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

extension Target.Dependency {
    /// Boost header-only modules required by Bitcoin Core v30.2 CMake.
    /// swift-boost doesn't declare inter-target deps, so we list them all explicitly.
    static let boostDeps: [Self] = [

        "assert", "bind", "config", "container_hash", "core", "describe",
        "detail", "foreach", "function", "integer", "iterator", "move",
        "mp11", "mpl", "multi_index", "optional", "preprocessor",
        "serialization", "signals2", "smart_ptr", "static_assert",
        "throw_exception", "tuple", "type_index", "type_traits",
        "utility", "variant",
    ].map { .product(name: $0, package: "swift-boost") }

    /// Dependencies for the libbitcoinkernel target.
    static let kernelDeps: [Self] = boostDeps + [
        .target(name: "crc32c"),
        .target(name: "leveldb"),
        .target(name: "secp256k1"),
    ]

    /// Dependencies for the bitcoind and walletsupport targets.
    static let bitcoinDeps: [Self] = kernelDeps + [
        .product(name: "libevent", package: "swift-libevent"),
        .target(name: "minisketch"),
        .target(name: "libbitcoinkernel"),
    ]
}

extension CXXSetting {
    /// Shared C++ settings for all Bitcoin Core C++ targets.
    static let shared: [Self] = [
        .headerSearchPath("src"),
        .headerSearchPath("src/univalue/include"),
        .define("BOOST_MULTI_INDEX_DISABLE_SERIALIZATION"),
    ]

    /// C++ settings for the bitcoind and walletsupport targets.
    static let bitcoinSettings: [Self] = shared + [
        .define("MAIN_FUNCTION", to: "int bitcoind_main(int argc, char* argv[])"),
        .define("G_TRANSLATION_FUN", to: "G_TRANSLATION_FUN_LOCAL"),
    ]

    /// C++ settings for the libbitcoinkernel target.
    static let kernelSettings: [Self] = shared + [
        .define("BITCOINKERNEL_BUILD", to: "1"),
    ]
}
