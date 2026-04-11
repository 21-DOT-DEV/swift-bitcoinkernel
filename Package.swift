// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Bitcoin",
    platforms: [
        .macOS(.v11),
        .iOS(.v14),
    ],
    products: [
        .library(name: "Bitcoin", targets: ["Bitcoin"]),
        .library(name: "BitcoinKernel", targets: ["BitcoinKernel"]),
    ],
    traits: [
        .trait(name: "wallet")
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
            name: "Bitcoin",
            dependencies: ["bitcoind", "RPCModels"],
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

        // MARK: - Swift Modules

        .target(name: "RPCModels"),

        // MARK: - Tests

        .testTarget(
            name: "BitcoinTests",
            dependencies: ["Bitcoin"],
            swiftSettings: SwiftSetting.bitcoinSettings
        ),
        .testTarget(
            name: "RPCModelsTests",
            dependencies: ["RPCModels"],
            resources: [.copy("Fixtures")]
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
    /// Boost header-only modules required by Bitcoin Core CMake.
    static let boostDeps: [Self] = [
        "assert", "bind", "config", "container_hash", "core", "describe",
        "detail", "foreach", "function", "integer", "iterator", "move",
        "mp11", "mpl", "multi_index", "optional", "preprocessor",
        "serialization", "signals2", "smart_ptr", "static_assert",
        "throw_exception", "tuple", "type_index", "type_traits",
        "utility", "variant",
    ].map { .product(name: $0, package: "swift-boost") }

    /// Dependencies for the libbitcoinkernel target.
    static let kernelDeps: [Self] =
        boostDeps + [
            .target(name: "crc32c"),
            .target(name: "leveldb"),
            .target(name: "secp256k1"),
        ]

    /// Dependencies for the bitcoind target.
    static let bitcoinDeps: [Self] =
        kernelDeps + [
            .product(name: "libevent", package: "swift-libevent"),
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
    /// Define shared across all Bitcoin Core C++ targets.
    static let boostDefine: Self = .define("BOOST_MULTI_INDEX_DISABLE_SERIALIZATION")

    /// Shared C++ settings for all Bitcoin Core C++ targets.
    static let shared: [Self] = [
        .headerSearchPath("src"),
        .headerSearchPath("src/univalue/include"),
        boostDefine,
    ]

    /// C++ settings for the bitcoind target.
    static let bitcoinSettings: [Self] =
        shared + [
            .define("MAIN_FUNCTION", to: "int bitcoind_main(int argc, char* argv[])"),
            .define("G_TRANSLATION_FUN", to: "G_TRANSLATION_FUN_LOCAL"),
            .define("ENABLE_WALLET", to: "1", .when(traits: ["wallet"])),
        ]

    /// C++ settings for the libbitcoinkernel target.
    static let kernelSettings: [Self] =
        shared + [
            .define("BITCOINKERNEL_BUILD", to: "1")
        ]
}
