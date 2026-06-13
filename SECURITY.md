# Security Policy

## Reporting a Vulnerability

Where you report depends on which component is affected. **Bitcoin Core consensus, network, and wallet bugs must go upstream**, not here — this repository will rebase on upstream fixes.

### Bitcoin Core (consensus, P2P, mempool, wallet, RPC server)

Vulnerabilities in the embedded Bitcoin Core sources under `Vendor/bitcoin/` and `Sources/{bitcoind,libbitcoinkernel}/` belong to upstream:

- See the [Bitcoin Core security reporting process](https://bitcoincore.org/en/contact/) (PGP-encrypted email to the security maintainers listed there).
- For consensus-affecting bugs, follow the upstream [responsible disclosure guidelines](https://bitcoincore.org/en/security-advisories/) before any public discussion.

### swift-bitcoinkernel Swift wrapper

Vulnerabilities specific to this package's Swift code — `RPCClient`, `Daemon`, `BitcoinConfig`, `BlockchainSync`, `BlockSource`, the `RPCTransport` family, and the response-model types under `Bitcoin/Models/` — should be reported via [GitHub Security Advisories](https://github.com/21-DOT-DEV/swift-bitcoinkernel/security/advisories).

**Do not file a public issue.**

When reporting, please include:

- A description of the vulnerability
- Steps to reproduce or a proof of concept
- Potential impact assessment (including funds-loss risk, if applicable)
- Whether the bug is in the Swift wrapper or in upstream Bitcoin Core (we will redirect upstream issues)

We will acknowledge receipt within 7 days and provide an initial assessment as soon as possible.

### Other 21-DOT-DEV components

This package depends on other 21-DOT-DEV libraries. Report vulnerabilities in those upstream:

- **swift-boost** (Boost C++ headers): [21-DOT-DEV/swift-boost security advisories](https://github.com/21-DOT-DEV/swift-boost/security/advisories)
- **swift-event** (libevent bindings): [21-DOT-DEV/swift-event security advisories](https://github.com/21-DOT-DEV/swift-event/security/advisories)
- General questions about the organization's policy: see the [21-DOT-DEV Security Policy](https://github.com/21-DOT-DEV/.github/blob/main/SECURITY.md).

### Other vendored upstream libraries

The package vendors additional upstream sources whose vulnerabilities should go directly to their respective projects:

- **secp256k1**: See [bitcoin-core/secp256k1 SECURITY.md](https://github.com/bitcoin-core/secp256k1/blob/master/SECURITY.md)
- **LevelDB**: See [google/leveldb security policy](https://github.com/google/leveldb/security/policy)
- **crc32c**: See [google/crc32c security policy](https://github.com/google/crc32c/security/policy)
- **minisketch**: See [bitcoin-core/minisketch](https://github.com/bitcoin-core/minisketch)

## Supported Versions

This package is pre-1.0 ([SemVer major version zero](https://semver.org/#spec-item-4)). Only the latest minor release receives security fixes.

| Version | Supported          |
|---------|--------------------|
| 0.1.x   | :white_check_mark: |
| < 0.1   | :x:                |

## Threat Model & Responsible Use

swift-bitcoinkernel runs Bitcoin Core in-process via `bitcoind` and links `libbitcoinkernel` for consensus validation. This has important implications:

- **Mainnet operations move real value.** Test on `regtest` or `signet` before pointing the daemon at mainnet, especially when integrating new code paths or upgrading versions.
- **Never log sensitive material.** Wallet seed phrases, BIP32 extended private keys, descriptor secrets, RPC cookies, and `bitcoin.conf` `rpcpassword=` lines must stay out of logs, crash reports, and analytics.
- **Match upstream Bitcoin Core's release cadence for security fixes.** Subscribe to [Bitcoin Core security advisories](https://bitcoincore.org/en/security-advisories/) — when upstream patches a consensus or wallet vulnerability, this package needs a corresponding subtree resync. Pin with `exact:` so you control when those rebases land in your build.
- **The `wallet` trait introduces additional attack surface.** Bitcoin Core's wallet (BDB/SQLite, descriptors, PSBT signing) is opt-in for a reason. Only enable it when your application actually custodies keys.

## Patch policy

For a consensus-validation package, the first question is whether local patches could change consensus behavior. They cannot. Modifications to the vendored Bitcoin Core sources are limited to build glue, platform guards, and process-lifecycle resets for in-process embedding. They never touch consensus, script, validation, or serialization code.

Every patch is documented in [`patches/`](patches/) with an upstreaming plan. The complete set of patched upstream files:

| File | Purpose |
|------|---------|
| `src/common/netif.cpp` | Guard route/sysctl headers absent from the iOS SDK |
| `src/rpc/server.cpp`, `src/rpc/server.h` | Remove one-shot `std::once_flag` so the RPC server can restart in-process |
| `src/init.cpp` | Reset process-global state at shutdown so a second `bitcoind_main()` can run |
| `src/compat/compat.h` | Guard `MAIN_FUNCTION` so the host app can own `main()` |
| `src/logging.cpp` | Prevent a teardown assertion when logging stops |

No patch modifies `src/consensus/`, `src/script/`, validation, or serialization. Subtree syncs overwrite the vendored sources wholesale, so drift outside `patches/` is structurally impossible. See [`patches/README.md`](patches/README.md) for the diffs and the upstreaming campaign.
