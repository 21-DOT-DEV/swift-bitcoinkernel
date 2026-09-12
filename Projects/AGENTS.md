# AGENTS.md (Projects)

Tuist-managed targets that complement the SPM package: two demo apps (`NodeApp`, `KernelApp`) and their UI/logic test bundles (`NodeAppTests`, `KernelAppTests`). The SPM test targets (`BitcoinTests`, `BitcoinKernelTests`) live under `Tests/` and are run with `swift test`, not through this workspace.

User-facing usage instructions live in [`README.md`](README.md). This file is deltas-only for maintainers editing the Tuist project.

## Commands

- Generate workspace: `swift package --disable-sandbox tuist generate -p Projects/ --no-open`
- Build an app (local): `swift package --disable-sandbox tuist build <NodeApp|KernelApp> -p Projects/ --platform <macos|ios>`
- Test an app (local): `swift package --disable-sandbox tuist test <NodeApp|KernelApp> -p Projects/ --platform <macos|ios>`
- Test everything locally on macOS: `swift package --disable-sandbox tuist test Bitcoin-Workspace -p Projects/ --platform macos`
- **What CI runs** ([`tuist-apps.yml`](../.github/workflows/tuist-apps.yml)): `tuist generate`, then `xcodebuild` directly on the generated workspace — `build-for-testing` then `test-without-building`, per app × platform. The split lets the iOS launch-crash retry re-run the tests without recompiling. CI uses `xcodebuild` rather than `tuist xcodebuild` because the `swift package tuist …` plugin can't forward xcodebuild's single-dash flags (SwiftPM's parser reads `-workspace`/`-scheme` as short-flag clusters and the `-c` inside grabs the value). Reproduce a CI build locally with `xcodebuild build-for-testing -skipMacroValidation -skipPackagePluginValidation -workspace Projects/Bitcoin.xcworkspace -scheme <NodeApp|KernelApp> -destination 'platform=macOS' -derivedDataPath .derivedData CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`, then the same with `test-without-building`.

## Non-obvious patterns

### Direct-product dependency model (no static-framework wrappers)

Every Tuist target depends directly on SPM products (`Bitcoin`, `BitcoinKernel`, `Tor`). There are intentionally no intermediate static-framework wrappers — keeps the project simple, build times fast, and avoids the symbol-visibility fights that come with re-exporting C++ types through a Swift framework.

### `Sources/Shared/` and `Sources/SharedTests/` are compiled into each app

Both `NodeApp` and `KernelApp` declare `sources: ["Sources/<App>/**", "Sources/Shared/**"]` in `Project.swift`, so the shared Tor view-model (`TorViewModel.swift`), the SwiftUI status view (`TorStatusView.swift`), the `URLSession`-over-Tor helper (`URLSessionConfiguration+Tor.swift`), and the node-diagnostics utility (`NodeDiagnostics.swift`) end up duplicated in each app's binary at compile time. Tests follow the same pattern with `Sources/SharedTests/**` (`FakeTorSession`, `SessionFactory`, `WaitFor`). `KernelAppTests` additionally reaches *up* to two files in the package's own test helpers (`../Tests/BitcoinKernelTests/Support/{KernelSerialization,AsyncSemaphore}.swift`), listed as explicit paths rather than a wildcard because that folder also holds a `MockBlockSource.swift` that would collide with this bundle's own. `WaitFor` polls the REAL clock and currently has zero callers — prefer injecting a `TestClock` into `TorViewModel(clock:)` or `KernelAppViewModel(clock:)`; see the note at the top of `WaitFor.swift`. When adding a file to `Sources/Shared/`, both apps pick it up automatically — no `Project.swift` edit needed.

### `swift-tor` is a workspace-only remote dependency

`Project.swift` pins Tor as a remote dependency, exact-versioned:

```swift
packages: [
    .package(path: ".."),
    .remote(url: "https://github.com/21-DOT-DEV/swift-tor.git", requirement: .exact("0.1.1")),
]
```

It is **deliberately not** declared in the root `Package.swift` — public SPM consumers of `Bitcoin`/`BitcoinKernel` shouldn't pay the resolution cost (or accept the closure of transitive deps from swift-tor) for a package only the demo apps use. Bumping the pin requires updating only this file. When editing `Project.swift`, never relax `.exact(...)` to `.upToNextMajor(...)` without an explicit ask — Tor's pre-1.0 API is not stable.

### Tor toggle / daemon coordination is the load-bearing demo logic

The `NodeApp` Tor integration is the most non-trivial part of the workspace. It demonstrates how a real consumer wires Tor into Bitcoin Core's `-proxy=` argument:

| Action | Result |
|---|---|
| Tor toggle ON | `TorClient` starts via `TorViewModel.start()`; bootstrap progress shown via `TorStatusView` |
| Tor toggle OFF | `TorClient` stops via `TorViewModel.stop()`; also clears `private_broadcast_enabled` in `UserDefaults` to prevent a stale pref from later leaking `-privatebroadcast=1` |
| Start Node (Tor off) | Allowed — `canStartNode = !torEnabled \|\| torViewModel.isReady` evaluates true; daemon launched without `-proxy=` |
| Start Node (Tor ready) | Daemon launched with `-proxy=<host>:<port>` from live SOCKS endpoint via `DaemonConfig.buildArguments(torProxy:)` |
| Start Node (Tor bootstrapping) | Start button disabled; "Waiting for Tor to bootstrap" hint shown (`ContentView.swift:84`) |
| Stop Node | `NodeViewModel.stop()` shuts down the daemon (sends `stop` RPC + `Daemon.waitUntilStopped()`); Tor lifecycle is independent and continues running until the user toggles it off |
| Private Broadcast toggle | UI gated by `!torEnabled \|\| !torViewModel.isReady` (`ConfigurationView.swift:169`). Even if the persisted pref is true, `DaemonConfig` further requires both `torEnabled` AND `torProxy != nil` before emitting `-privatebroadcast=1` (`DaemonConfig.swift:75`). |

Key files:

| File | Purpose |
|---|---|
| `Sources/Shared/TorViewModel.swift` | Tor lifecycle (`@Observable`, `@MainActor`); compiled into both `NodeApp` and `KernelApp` |
| `Sources/Shared/TorStatusView.swift` | SwiftUI status indicator shared across both apps |
| `Sources/Shared/URLSessionConfiguration+Tor.swift` | SOCKS5 helper for `URLSession` over Tor |
| `Sources/NodeApp/DaemonConfig.swift` | Type-safe `BitcoinConfig` argument builder; `static func buildArguments(torProxy: String? = nil) -> [String]` |
| `Sources/NodeAppTests/TorViewModelTests.swift` | Unit tests for state-machine logic (no network) |
| `Sources/NodeAppTests/TorIntegrationTests.swift` | Live Tor lifecycle test, marked `.disabled("Requires network access — run manually")` |

### `DaemonConfig.buildArguments(torProxy:)` contract

Builds daemon CLI arguments using `BitcoinConfig` from the `Bitcoin` library:

```swift
// Without Tor
let args = DaemonConfig.buildArguments()

// With Tor (proxy address from TorViewModel)
let args = DaemonConfig.buildArguments(torProxy: torViewModel.proxyAddress)
```

When `torProxy` is `nil` and `tor_enabled` is true, the `-proxy=` argument is omitted (Tor not yet bootstrapped — the daemon should start *without* a stale proxy and reconnect later). When `tor_enabled` is false, the `torProxy` parameter is ignored.

### Manual Tor integration testing (network-gated)

`TorIntegrationTests` is `.disabled` so CI never depends on the live Tor network. To run manually:

```bash
xcodebuild test \
    -workspace Projects/Bitcoin.xcworkspace \
    -scheme Bitcoin-Workspace \
    -destination 'platform=macOS' \
    -only-testing:NodeAppTests/TorIntegrationTests
```

Tor bootstrap takes 30–60s cold (5–10s with cached consensus); the test has a 3-minute timeout.

### Privacy manifests (required-reason declarations)

Both apps ship `Resources/<App>/PrivacyInfo.xcprivacy` (bundled via `resources:` in `Project.swift`) and both declare the same four categories — `UserDefaults`/`CA92.1` plus `FileTimestamp`/`C617.1`, `DiskSpace`/`E174.1` and `SystemBootTime`/`35F9.1`. The identical set is deliberate, not copy-paste sloppiness: the vendored kernel/daemon C++ links *statically* into each app executable, so its `stat`/`statfs`/`sysctl(KERN_BOOTTIME)` calls are the app's calls at upload validation — SDK resource-bundle manifests are not reliably consulted (see firebase-ios-sdk#12557). The package's own product-target manifests (`Sources/Bitcoin{,Kernel}/PrivacyInfo.xcprivacy`) exist for consumers' privacy reports, not as a substitute. If a subtree sync adds or drops a required-reason call site, update all four manifests together. `35F9.1` is the closest approved fit for `randomenv.cpp`'s entropy mixing of `kern.boottime` — no reason literally says "entropy."

### Entitlements

Both `NodeApp.entitlements` and `KernelApp.entitlements` declare:

- `com.apple.security.network.client` — required for Tor SOCKS outbound connections and (in `NodeApp`) HTTP RPC traffic to the local daemon.
- `com.apple.security.network.server` — `NodeApp` uses this for the local RPC listener bound by `bitcoind`. `KernelApp` ships with it for parity but does not currently bind a server port; revisit on the next entitlements review and drop it from `KernelApp` if no inbound listener has shipped.

### Shared/Debug/Release xcconfig pattern

Project-level and app targets use a three-file xcconfig layout under `Resources/<Target>/`:

- `Shared.xcconfig` — common settings (versioning, module verifier, security analyzers)
- `Debug.xcconfig` — `#include "Shared.xcconfig"` + debug overrides
- `Release.xcconfig` — `#include "Shared.xcconfig"` + release overrides

The Project layer additionally has `Resources/Project/Local.xcconfig` for developer-machine overrides (gitignored). The test bundles (`NodeAppTests`, `KernelAppTests`) currently use only `Debug.xcconfig` + `Release.xcconfig` — if a test target grows enough common configuration to warrant it, lift it to a `Shared.xcconfig` rather than duplicating across both files.

When adding a new target, follow this pattern rather than putting all settings in `Project.swift` — keeps build configuration auditable in plain text.

## Platforms

- **macOS 15+** — primary; every target builds and runs in CI.
- **iOS 18+** — both `NodeApp` and `KernelApp` declare `destinations: [.iPhone, .iPad, .mac]` in `Project.swift` and have iOS-specific UI paths (`#if !os(macOS)` blocks in `ConfigurationView.swift`, `CommandDetailView.swift`, etc.). Both apps build and run their test bundles on the iOS Simulator on every push/PR via [`tuist-apps.yml`](../.github/workflows/tuist-apps.yml). If iOS regressions surface (e.g. from the next Bitcoin Core subtree sync touching `<sys/random.h>`, `<net/route.h>`, or `<sys/sysctl.h>`), check `patches/bitcoin/ios-netif-guard.md` for the existing carve-out pattern.
- **visionOS 2+ / tvOS 18+** — staged as commented matrix rows in `tuist-apps.yml`. tvOS carries `KernelApp` only (the `Bitcoin` product's `execvp()` is `__TVOS_PROHIBITED`), mirroring the per-scheme split in `apple-builds.yml`.

## Boundaries

- **Never**: introduce intermediate static-framework wrappers around SPM products; relax the `swift-tor` pin in `Project.swift` from `.exact(...)` to `.upToNextMajor(...)` or `.branch(...)` (Tor's pre-1.0 API is not stable); enable `TorIntegrationTests` in CI; commit Xcode-generated `xcuserdata` or per-developer scheme overrides.
- **Ask first**: add a new demo app target; bump platform deployment targets; add a third-party Tuist plugin.

## Maintenance

- Update `README.md` (user-facing) and this file (maintainer-facing) together when the workspace structure changes.
- When a new demo app target is added to `Project.swift`, also add it to `README.md`'s "Demo apps" table and to `tuist-apps.yml`'s matrix.
- When CI platform coverage for the apps changes, update `tuist-apps.yml`'s matrix and the Platforms section above together.
- When a new SPM product is added to root `Package.swift`, decide whether either demo app should consume it.
