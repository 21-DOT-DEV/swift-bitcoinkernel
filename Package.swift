// swift-tools-version: 5.9
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
            dependencies: bitcoinDependencies(),
            exclude: ["src/crypto/ctaes/ctaes.c"],
            publicHeadersPath: "include",
            cxxSettings: cxxSettings()
        ),
        .target(
            name: "walletsupport",
            dependencies: bitcoinDependencies(),
            exclude: ["src/crypto/ctaes/ctaes.c"],
            publicHeadersPath: "include",
            cxxSettings: cxxSettings(),
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
        .testTarget(
            name: "BitcoinTests",
            dependencies: [
                "Bitcoin"
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
    ],
    swiftLanguageVersions: [.v5],
    cLanguageStandard: .c89,
    cxxLanguageStandard: .cxx20
)

// MARK: - Helper Functions

func bitcoinDependencies() -> [Target.Dependency] {
    // Boost modules are all header-only. multi_index and signals2 are the direct
    // dependencies (per Bitcoin Core v30.2 CMake), but their headers transitively
    // include most other Boost modules. swift-boost doesn't declare inter-target
    // deps, so we list them all explicitly.
    let boostModules: [String] = [
        "assert", "bind", "config", "container_hash", "core", "describe",
        "detail", "foreach", "function", "integer", "iterator", "move",
        "mp11", "mpl", "multi_index", "optional", "preprocessor",
        "serialization", "signals2", "smart_ptr", "static_assert",
        "throw_exception", "tuple", "type_index", "type_traits",
        "utility", "variant",
    ]
    return boostModules.map { .product(name: $0, package: "swift-boost") } + [
        .product(name: "libevent", package: "swift-libevent"),
        .target(name: "crc32c"),
        .target(name: "leveldb"),
        .target(name: "minisketch"),
        .target(name: "secp256k1")
    ]
}

func cxxSettings() -> [CXXSetting] {
    [
        .headerSearchPath("src"),
        .headerSearchPath("src/univalue/include"),
        .define("BOOST_MULTI_INDEX_DISABLE_SERIALIZATION"),
        .define("MAIN_FUNCTION", to: "int bitcoind_main(int argc, char* argv[])")
    ]
}
