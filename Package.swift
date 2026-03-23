// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Bitcoin",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13)
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
        .package(url: "https://github.com/21-DOT-DEV/swift-berkeleydb", branch: "main"),
        .package(url: "https://github.com/21-DOT-DEV/swift-plugin-subtree.git", exact: "0.0.12"),
    ],
    targets: [
        .target(
            name: "bitcoind",
            dependencies: bitcoinDependencies(),
            exclude: ["include/crypto/ctaes/ctaes.c"],
            publicHeadersPath: "include",
            cxxSettings: cxxSettings()
        ),
        .target(
            name: "walletsupport",
            dependencies: bitcoinDependencies() + [
                .product(name: "BerkeleyDB", package: "swift-berkeleydb"),
                .product(name: "algorithm", package: "swift-boost"),
                .product(name: "array", package: "swift-boost"),
                .product(name: "concept_check", package: "swift-boost"),
                .product(name: "container", package: "swift-boost"),
                .product(name: "date_time", package: "swift-boost"),
                .product(name: "io", package: "swift-boost"),
                .product(name: "lexical_cast", package: "swift-boost"),
                .product(name: "numeric_conversion", package: "swift-boost"),
                .product(name: "range", package: "swift-boost"),
                .product(name: "tokenizer", package: "swift-boost")
            ],
            exclude: ["include/crypto/ctaes/ctaes.c"],
            publicHeadersPath: "include",
            cxxSettings: cxxSettings()
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
                .define("ENABLE_MODULE_ECDH"),
                .define("ENABLE_MODULE_ELLSWIFT"),
                .define("ENABLE_MODULE_EXTRAKEYS"),
                .define("ENABLE_MODULE_RECOVERY"),
                .define("ENABLE_MODULE_SCHNORRSIG")
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
    cxxLanguageStandard: .cxx17
)

// MARK: - Helper Functions

func bitcoinDependencies() -> [Target.Dependency] {
    [
        .product(name: "assert", package: "swift-boost"),
        .product(name: "bind", package: "swift-boost"),
        .product(name: "config", package: "swift-boost"),
        .product(name: "container_hash", package: "swift-boost"),
        .product(name: "core", package: "swift-boost"),
        .product(name: "describe", package: "swift-boost"),
        .product(name: "detail", package: "swift-boost"),
        .product(name: "foreach", package: "swift-boost"),
        .product(name: "function", package: "swift-boost"),
        .product(name: "integer", package: "swift-boost"),
        .product(name: "iterator", package: "swift-boost"),
        .product(name: "move", package: "swift-boost"),
        .product(name: "mp11", package: "swift-boost"),
        .product(name: "mpl", package: "swift-boost"),
        .product(name: "multi_index", package: "swift-boost"),
        .product(name: "optional", package: "swift-boost"),
        .product(name: "preprocessor", package: "swift-boost"),
        .product(name: "serialization", package: "swift-boost"),
        .product(name: "signals2", package: "swift-boost"),
        .product(name: "smart_ptr", package: "swift-boost"),
        .product(name: "static_assert", package: "swift-boost"),
        .product(name: "throw_exception", package: "swift-boost"),
        .product(name: "tuple", package: "swift-boost"),
        .product(name: "type_index", package: "swift-boost"),
        .product(name: "type_traits", package: "swift-boost"),
        .product(name: "utility", package: "swift-boost"),
        .product(name: "variant", package: "swift-boost"),
        .product(name: "libevent", package: "swift-libevent"),
        .target(name: "crc32c"),
        .target(name: "leveldb"),
        .target(name: "minisketch"),
        .target(name: "secp256k1")
    ]
}

func cxxSettings() -> [CXXSetting] {
    [
        //  .unsafeFlags(["-D","BOOST_NO_CXX98_FUNCTION_BASE"]),
        .headerSearchPath("src"),
        .define("HAVE_GMTIME_R", to: "\(haveGmtimeR())"),
        .define("CLIENT_VERSION_IS_RELEASE", to: "true"),
        .define("CLIENT_VERSION_MAJOR", to: "26"),
        .define("CLIENT_VERSION_MINOR", to: "0"),
        .define("CLIENT_VERSION_BUILD", to: "0"),
        .define("COPYRIGHT_YEAR", to: "2023"),
        .define("COPYRIGHT_HOLDERS", to: "\"The %s developers\""),
        .define("COPYRIGHT_HOLDERS_SUBSTITUTION", to: "\"Bitcoin Core\""),
        .define("PACKAGE_NAME", to: "\"Bitcoin Core\""),
        .define("PACKAGE_BUGREPORT", to: "\"https://github.com/bitcoin/bitcoin/issues\""),
        .define("PACKAGE_URL", to: "\"https://bitcoincore.org/\""),
        .define("PACKAGE_VERSION", to: "\"26.0.0\""),
        .define("BOOST_NO_CXX98_FUNCTION_BASE")
    ]
}

func haveGmtimeR() -> Int {
    #if os(iOS)
    // Define HAVE_GMTIME_R in Swift context
    0
    #else
    0
    #endif
}
