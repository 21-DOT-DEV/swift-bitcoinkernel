// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

#if os(iOS)
// Define HAVE_GMTIME_R in Swift context
let haveGmtimeR = 0
#else
let haveGmtimeR = 1
#endif

let package = Package(
    name: "Bitcoin",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13)
    ],

    products: [
        .library(name: "Bitcoin", targets: ["Bitcoin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/21-DOT-DEV/libevent.swift.git", branch: "main"),
        .package(url: "https://github.com/21-DOT-DEV/Boost.swift.git", exact: "1.80.0"),
    ],
    targets: [
        .target(
            name: "bitcoind",
            dependencies: [
                .product(name: "assert", package: "Boost.swift"),
                .product(name: "bind", package: "Boost.swift"),
                .product(name: "config", package: "Boost.swift"),
                .product(name: "container_hash", package: "Boost.swift"),
                .product(name: "core", package: "Boost.swift"),
                .product(name: "detail", package: "Boost.swift"),
                .product(name: "foreach", package: "Boost.swift"),
                .product(name: "function", package: "Boost.swift"),
                .product(name: "integer", package: "Boost.swift"),
                .product(name: "iterator", package: "Boost.swift"),
                .product(name: "move", package: "Boost.swift"),
                .product(name: "mpl", package: "Boost.swift"),
                .product(name: "multi_index", package: "Boost.swift"),
                .product(name: "optional", package: "Boost.swift"),
                .product(name: "preprocessor", package: "Boost.swift"),
                .product(name: "serialization", package: "Boost.swift"),
                .product(name: "signals2", package: "Boost.swift"),
                .product(name: "smart_ptr", package: "Boost.swift"),
                .product(name: "static_assert", package: "Boost.swift"),
                .product(name: "throw_exception", package: "Boost.swift"),
                .product(name: "tuple", package: "Boost.swift"),
                .product(name: "type_index", package: "Boost.swift"),
                .product(name: "type_traits", package: "Boost.swift"),
                .product(name: "utility", package: "Boost.swift"),
                .product(name: "variant", package: "Boost.swift"),
                .product(name: "libevent", package: "libevent.swift"),
                .target(name: "crc32c"),
                .target(name: "leveldb"),
                .target(name: "minisketch"),
                .target(name: "secp256k1")
            ],
            exclude: ["include/crypto/ctaes/ctaes.c"],
            publicHeadersPath: "include",
            cxxSettings: [
//                .unsafeFlags(["-D","BOOST_NO_CXX98_FUNCTION_BASE"]),
                .headerSearchPath("src"),
                .define("HAVE_GMTIME_R", to: "\(haveGmtimeR)"),
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
        ),
        .target(
            name: "Bitcoin",
            dependencies: ["bitcoind"],
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
