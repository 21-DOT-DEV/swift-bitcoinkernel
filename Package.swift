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
            exclude: ["src/crypto/ctaes/ctaes.c"] + kernelSourceExcludes(),
            publicHeadersPath: "include",
            cxxSettings: cxxSettings()
        ),
        .target(
            name: "walletsupport",
            dependencies: bitcoinDependencies(),
            exclude: ["src/crypto/ctaes/ctaes.c"] + kernelSourceExcludes(),
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
        .target(
            name: "libbitcoinkernel",
            dependencies: kernelDependencies(),
            exclude: ["src/crypto/ctaes/ctaes.c"],
            publicHeadersPath: "include",
            cxxSettings: kernelCxxSettings()
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
        .target(name: "secp256k1"),
        .target(name: "libbitcoinkernel"),
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

func kernelDependencies() -> [Target.Dependency] {
    let boostModules: [String] = [
        "assert", "bind", "config", "container_hash", "core", "describe",
        "detail", "foreach", "function", "integer", "iterator", "move",
        "mp11", "mpl", "multi_index", "optional", "preprocessor",
        "serialization", "signals2", "smart_ptr", "static_assert",
        "throw_exception", "tuple", "type_index", "type_traits",
        "utility", "variant",
    ]
    return boostModules.map { .product(name: $0, package: "swift-boost") } + [
        .target(name: "crc32c"),
        .target(name: "leveldb"),
        .target(name: "secp256k1"),
    ]
}

func kernelCxxSettings() -> [CXXSetting] {
    [
        .headerSearchPath("src"),
        .headerSearchPath("src/univalue/include"),
        .define("BITCOINKERNEL_BUILD", to: "1"),
        .define("BOOST_MULTI_INDEX_DISABLE_SERIALIZATION"),
    ]
}

/// Kernel .cpp sources that bitcoind/walletsupport must exclude to avoid
/// duplicate symbols — these are compiled by libbitcoinkernel instead.
/// Matches the brace-expansion patterns in subtree.yaml.
func kernelSourceExcludes() -> [String] {
    [
        // kernel/
        "src/kernel/chain.cpp",
        "src/kernel/checks.cpp",
        "src/kernel/chainparams.cpp",
        "src/kernel/coinstats.cpp",
        "src/kernel/context.cpp",
        "src/kernel/cs_main.cpp",
        "src/kernel/disconnected_transactions.cpp",
        "src/kernel/mempool_removal_reason.cpp",
        // src/
        "src/arith_uint256.cpp",
        "src/chain.cpp",
        "src/clientversion.cpp",
        "src/coins.cpp",
        "src/compressor.cpp",
        "src/dbwrapper.cpp",
        "src/deploymentinfo.cpp",
        "src/deploymentstatus.cpp",
        "src/flatfile.cpp",
        "src/hash.cpp",
        "src/logging.cpp",
        "src/pow.cpp",
        "src/pubkey.cpp",
        "src/random.cpp",
        "src/randomenv.cpp",
        "src/signet.cpp",
        "src/streams.cpp",
        "src/sync.cpp",
        "src/txdb.cpp",
        "src/txgraph.cpp",
        "src/txmempool.cpp",
        "src/uint256.cpp",
        "src/validation.cpp",
        "src/validationinterface.cpp",
        "src/versionbits.cpp",
        // consensus/
        "src/consensus/merkle.cpp",
        "src/consensus/tx_check.cpp",
        "src/consensus/tx_verify.cpp",
        // crypto/
        "src/crypto/aes.cpp",
        "src/crypto/chacha20.cpp",
        "src/crypto/chacha20poly1305.cpp",
        "src/crypto/hex_base.cpp",
        "src/crypto/hkdf_sha256_32.cpp",
        "src/crypto/hmac_sha256.cpp",
        "src/crypto/hmac_sha512.cpp",
        "src/crypto/muhash.cpp",
        "src/crypto/poly1305.cpp",
        "src/crypto/ripemd160.cpp",
        "src/crypto/sha1.cpp",
        "src/crypto/sha256.cpp",
        "src/crypto/sha256_sse4.cpp",
        "src/crypto/sha3.cpp",
        "src/crypto/sha512.cpp",
        "src/crypto/siphash.cpp",
        // node/
        "src/node/blockstorage.cpp",
        "src/node/chainstate.cpp",
        "src/node/utxo_snapshot.cpp",
        // policy/
        "src/policy/ephemeral_policy.cpp",
        "src/policy/feerate.cpp",
        "src/policy/packages.cpp",
        "src/policy/policy.cpp",
        "src/policy/rbf.cpp",
        "src/policy/settings.cpp",
        "src/policy/truc_policy.cpp",
        // primitives/
        "src/primitives/block.cpp",
        "src/primitives/transaction.cpp",
        // script/
        "src/script/interpreter.cpp",
        "src/script/script.cpp",
        "src/script/script_error.cpp",
        "src/script/sigcache.cpp",
        "src/script/solver.cpp",
        // support/
        "src/support/cleanse.cpp",
        "src/support/lockedpool.cpp",
        // util/
        "src/util/chaintype.cpp",
        "src/util/check.cpp",
        "src/util/expected.cpp",
        "src/util/feefrac.cpp",
        "src/util/fs.cpp",
        "src/util/fs_helpers.cpp",
        "src/util/hasher.cpp",
        "src/util/moneystr.cpp",
        "src/util/rbf.cpp",
        "src/util/serfloat.cpp",
        "src/util/signalinterrupt.cpp",
        "src/util/syserror.cpp",
        "src/util/threadnames.cpp",
        "src/util/time.cpp",
        "src/util/tokenpipe.cpp",
    ]
}

