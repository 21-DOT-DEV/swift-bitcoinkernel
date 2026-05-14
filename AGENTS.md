# AGENTS.md (swift-bitcoin)

A Swift 6.3 package wrapping Bitcoin Core for embedded use: daemon lifecycle (`Bitcoin` target) and consensus validation (`BitcoinKernel` target). Supports macOS 15+, iOS 18+ (Tier 1); Linux, tvOS, visionOS (Tier 2 aspirational). Uses Swift C++ interoperability mode and C++20.

## Commands

- Build: `swift build`
- Test: `swift test`
- Build with wallet trait: `swift build --traits wallet`
- Test with wallet trait: `swift test --traits wallet`
- Subtree sync: `swift package plugin subtree-sync` (updates vendored Bitcoin Core sources)
- Tuist generate: `swift package --disable-sandbox tuist generate -p Projects/ --no-open`
- Tuist build (iOS): `swift package --disable-sandbox tuist build Bitcoin -p Projects/ --platform ios`

## Non-obvious patterns

- **C++ interop**: All Bitcoin Core bindings use `.interoperabilityMode(.Cxx)` (`Package.swift` line 145). C++ exceptions must be caught at the Swift boundary and converted to Swift errors — they must NOT propagate into Swift code. Unsafe code is isolated behind clearly named abstractions; public API callers never reason about C++ lifetimes.
- **Dual targets**: `Bitcoin` wraps `bitcoind` (embedded daemon + RPC client). `BitcoinKernel` wraps `libbitcoinkernel` (consensus validation only). `BitcoinKernel` is a node layer consumed by wallets/SDKs, not a wallet itself.
- **Wallet trait**: Wallet functionality is gated behind the `wallet` package trait. Xcode does not resolve `.when(traits:)` for Swift settings, so source files use `#if Xcode || ENABLE_WALLET` guards — preserve these when editing.
- **Subtree extraction flow**: Vendor/bitcoin → Sources via `swift-plugin-subtree`. Do NOT edit files under `Sources/{bitcoind,libbitcoinkernel,crc32c,leveldb,minisketch,secp256k1}/` directly; changes are overwritten on next extraction. Local modifications for SPM/embedded use are maintained as patches under `patches/bitcoin/`. Hand-written `module.modulemap` stubs and `bitcoin-build-config.h` replacements live under `Sources/` alongside vendored code but survive extraction because subtree patterns only match `*.{h,c,cc,cpp}`; see `patches/README.md` § "Non-patch custom files" for the full list.
- **BlockchainSync**: Value-type configuration (`BlockchainSync`) exposing a typed `AsyncSequence` of `Update` snapshots. Follows Apple's `CLLocationUpdate.liveUpdates(_:)` pattern. Cancel by breaking the `for await` loop or cancelling the enclosing `Task`; cleanup calls `Context.interrupt()`. Errors arrive as `.failed(reason)` terminal states (non-throwing). Foundation.Progress is KVO-observable for SwiftUI and BGContinuedProcessingTask integration.
- **BlockSource protocol**: Hash-addressed block delivery (`BlockSource`). All `Data` hashes are in internal (kernel) byte order. Implementations speaking to external services that use display-order hex (Esplora) are responsible for reversing bytes at the boundary.
- **Tor integration**: SOCKS5 proxy via `URLSession` configuration. `EsploraBlockSource` accepts a proxied session for Tor-routed block downloads. `Daemon.start()` calls `bitcoin_socks_reset()` to clear the sticky `g_socks5_interrupt` flag between in-process restarts.
- **RPC transport**: `RPCTransport` protocol with 5 implementations: `DirectTransport` (in-process C bridge), `HTTPTransport` (HTTP with Basic auth), `CookieTransport` (cookie file auth), `AutoTransport` (auto-detects best transport per call). `AutoTransport` routes non-wallet RPCs through `DirectTransport` and wallet RPCs through `HTTPTransport`.
- **Configuration builder**: `BitcoinConfig` uses phantom types for network scoping. Options are additive (each method returns `Self`). Use presets (`BitcoinConfig.regtest`, `.signet`, etc.) for common configurations.

## Boundaries

- **Never**: emit private keys or sensitive material; weaken constant-time code in vendored C sources; edit files under `Vendor/bitcoin/` or extracted `Sources/{bitcoind,libbitcoinkernel,secp256k1,...}/` directly; add runtime dependencies outside the allowlist (`swift-boost`, `swift-event`, system `sqlite3`) without a constitutional amendment; reimplement Bitcoin consensus rules, validation logic, or P2P protocol behavior in Swift; expose raw C++ pointers or types through public Swift API.
- **Ask first**: add new third-party dependencies; broaden CI permissions; add runtime dependencies outside the allowlist; change the pinned Bitcoin Core version in `subtree.yaml`.
- See the [21-DOT-DEV contributing guidelines](https://github.com/21-DOT-DEV/.github/blob/main/CONTRIBUTING.md) for branching and commit guidelines.

## Scoped guidance

Directory-specific `AGENTS.md` files provide additional context:

- `Projects/AGENTS.md` — Tuist-managed targets, XCFramework workflows

## Maintenance

- Keep scoped `AGENTS.md` files limited to deltas; avoid duplicating root guidance.
- Update when build/test workflows, toolchain versions, platform requirements, or CI runners change.
- Update when new phases from `.specify/memory/roadmap.md` are completed.