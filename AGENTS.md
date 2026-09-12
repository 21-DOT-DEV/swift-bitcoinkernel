# AGENTS.md (swift-bitcoinkernel)

A Swift 6.3 package wrapping Bitcoin Core: daemon lifecycle (`Bitcoin` target) and consensus validation (`BitcoinKernel` target). Supports macOS 15+, iOS 18+, visionOS 2+, and tvOS 18+ (BitcoinKernel only — `Bitcoin` depends on `execvp()`, marked `__TVOS_PROHIBITED`). Uses Swift C++ interoperability mode and C++20.

## Commands

- Build: `swift build`
- Test: `swift test`
- Build/test with wallet trait: `swift build --traits wallet` / `swift test --traits wallet`
- Subtree sync: `swift package plugin subtree-sync` (updates vendored Bitcoin Core sources)
- Generate DocC: `swift package generate-documentation --target Bitcoin --analyze --warnings-as-errors` (repeat for `BitcoinKernel`)

Tuist workspace commands live in [`Projects/AGENTS.md`](Projects/AGENTS.md).

## Non-obvious patterns

- **C++ interop**: The `Bitcoin` Swift target uses `.interoperabilityMode(.Cxx)` (see `SwiftSetting.bitcoinSettings` in `Package.swift`). C++ exceptions must be caught at the Swift boundary and converted to Swift errors — they must NOT propagate into Swift code. Unsafe code is isolated behind clearly named abstractions; public API callers never reason about C++ lifetimes.
- **Dual targets**: `Bitcoin` wraps `bitcoind` (embedded daemon + RPC client). `BitcoinKernel` wraps `libbitcoinkernel` (consensus validation only). `BitcoinKernel` is a node layer consumed by wallets/SDKs, not a wallet itself.
- **Wallet trait**: Wallet functionality is gated behind the `wallet` package trait. Xcode does not resolve `.when(traits:)` for Swift settings, so source files use `#if Xcode || ENABLE_WALLET` guards — preserve these when editing.
- **Subtree extraction flow**: `Vendor/bitcoin/` → `Sources/{bitcoind,libbitcoinkernel,crc32c,leveldb,minisketch,secp256k1}/` via `swift-plugin-subtree`. Do NOT edit extracted files directly; changes are overwritten on next extraction. Local modifications for SPM/embedded use are maintained as patches under `patches/bitcoin/`. Hand-written `module.modulemap` stubs and `bitcoin-build-config.h` replacements survive extraction because subtree patterns only match `*.{h,c,cc,cpp}` — see `patches/README.md` § "Non-patch custom files".
- **BlockchainSync**: Value-type configuration (`BlockchainSync`) exposing a typed `AsyncSequence` of `Update` snapshots. Follows Apple's `CLLocationUpdate.liveUpdates(_:)` pattern. Cancel by breaking the `for await` loop or cancelling the enclosing `Task`; cleanup calls `Context.interrupt()`. Errors arrive as `.failed(reason)` terminal states (non-throwing). `Foundation.Progress` is KVO-observable for SwiftUI and `BGContinuedProcessingTask` integration.
- **BlockSource protocol**: Hash-addressed block delivery. All `Data` hashes are in internal (kernel) byte order. Implementations speaking to external services that use display-order hex (Esplora) are responsible for reversing bytes at the boundary.
- **Privacy manifests**: `Sources/Bitcoin/PrivacyInfo.xcprivacy` and `Sources/BitcoinKernel/PrivacyInfo.xcprivacy` ship in each product's resource bundle (Darwin-gated `.copy` + `exclude`, the swift-crypto pattern) declaring the required-reason calls the vendored C++ makes: `FileTimestamp`/`C617.1` (`stat`/`fstat`/`fs::file_size`), `DiskSpace`/`E174.1` (`fs::space`, `statfs`), `SystemBootTime`/`35F9.1` (`sysctl(KERN_BOOTTIME)` in `randomenv.cpp`). Recheck against a grep after every subtree sync — the manifests describe upstream code, so upstream changes can invalidate them.
- **Tor integration**: SOCKS5 proxy via `URLSession` configuration. `EsploraBlockSource` accepts a proxied session for Tor-routed block downloads. `Daemon.start()` calls `bitcoin_socks_reset()` to clear the sticky `g_socks5_interrupt` flag between in-process restarts.
- **RPC transport**: `RPCTransport` protocol with 4 implementations: `DirectTransport` (in-process C bridge), `HTTPTransport` (Basic auth, conforms to `WalletCapableTransport`), `CookieTransport` (cookie file auth, conforms to `WalletCapableTransport`), `AutoTransport` (auto-detects best transport per call). `AutoTransport` routes non-wallet RPCs through `DirectTransport` and wallet RPCs through the configured HTTP transport.
- **Configuration builder**: `BitcoinConfig` uses phantom types for network scoping. Options are additive (each method returns `Self`). Use presets (`BitcoinConfig.regtest()`, `.signet()`, etc.) for common configurations.

## Boundaries

- **Never**: emit private keys or sensitive material; weaken constant-time code in vendored C sources; edit files under `Vendor/bitcoin/` or extracted `Sources/{bitcoind,libbitcoinkernel,secp256k1,...}/` directly; add runtime dependencies outside the allowlist (`swift-boost`, `swift-event`, system `sqlite3`) without a constitutional amendment; reimplement Bitcoin consensus rules, validation logic, or P2P protocol behavior in Swift; expose raw C++ pointers or types through public Swift API.
- **Ask first**: add new third-party dependencies; broaden CI permissions; change the pinned Bitcoin Core version in `subtree.yaml`.
- **At release (tag time)**: pin every dependency to `exact:` or `revision:`. Never ship a tagged release with a `branch:` requirement, which is non-reproducible.
- See the [21-DOT-DEV contributing guidelines](https://github.com/21-DOT-DEV/.github/blob/main/CONTRIBUTING.md) for branching and commit guidelines. See [SECURITY.md](SECURITY.md) for vulnerability reporting.

## Scoped guidance

Directory-specific `AGENTS.md` files provide additional context:

- [`.github/AGENTS.md`](.github/AGENTS.md) — CI workflows, platform coverage matrix, Actions permissions policy
- [`Projects/AGENTS.md`](Projects/AGENTS.md) — Tuist-managed demo apps, XCFramework workflows

## Planning artifacts

Everything about how this project is developed lives under
[`Development/`](Development/README.md): the charter (`constitution.md`), the phase plan
(`Roadmap/`), one `plan.md` per feature (`Specs/`), and the decision records (`ADRs/`).
That folder's README is authoritative for what goes where and this file does not repeat
it.

Two rules are worth knowing before writing anything there. A plan is **corrected in
place** when review changes its design, never appended to with a note saying an earlier
section is now wrong. A decision that outlives its feature becomes an ADR. Plans carry
no status log, review log, or round-by-round history.

## Maintenance

- Keep scoped `AGENTS.md` files limited to deltas; avoid duplicating root guidance.
- Update when build/test workflows, toolchain versions, platform requirements, or CI runners change.
- Update when new phases from [`Development/Roadmap/`](Development/Roadmap/README.md) are completed.
- Plan non-trivial features as `Development/Specs/NNN-slug/plan.md`, starting from
  `Development/Specs/_template/plan.md`. A feature's status lives in that plan's frontmatter
  and nowhere else; the index tables are generated by `Development/Tools`
  (`swift run --package-path Development/Tools plans`).
