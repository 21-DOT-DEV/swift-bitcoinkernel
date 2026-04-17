# Bitcoin Tuist Project

Tuist-managed Xcode workspace with example apps, framework tests, and upstream vector tests for the `Bitcoin` and `BitcoinKernel` Swift packages.

## Quick Start

```bash
# Generate Xcode project
swift package --disable-sandbox tuist generate -p Projects/ --no-open

# Build all apps (macOS)
swift package --disable-sandbox tuist build NodeApp -p Projects/ --platform macos
swift package --disable-sandbox tuist build KernelApp -p Projects/ --platform macos
swift package --disable-sandbox tuist build XCFrameworkApp -p Projects/ --platform macos

# Run all tests
swift package --disable-sandbox tuist test Bitcoin-Workspace -p Projects/ --platform macos

# xcodebuild fallback
xcodebuild test -workspace Projects/Bitcoin.xcworkspace -scheme BitcoinTests -destination 'platform=macOS'
```

## Targets

### Example Apps

| Target | Description | Dependencies |
|--------|-------------|-------------|
| **NodeApp** | Full-node demo (RPC, Daemon, Tor) | `Bitcoin`, `Tor` |
| **KernelApp** | Kernel-only demo (chain types, Tor plumbing) | `BitcoinKernel`, `Tor` |
| **XCFrameworkApp** | Multi-library demo (both modules) | `Bitcoin`, `BitcoinKernel` |

### Test Targets

| Target | Description | Dependencies |
|--------|-------------|-------------|
| **BitcoinTests** | Bitcoin library tests | `Bitcoin` (SPM) |
| **BitcoinKernelTests** | BitcoinKernel library tests | `BitcoinKernel` (SPM) |
| **NodeAppTests** | NodeApp UI/logic tests + Tor tests | `NodeApp` |
| **KernelAppTests** | KernelApp UI/logic tests | `KernelApp` |
| **RPCModelsTests** | RPC model decoding tests | `Bitcoin` (SPM) |
| **ScriptVectorTests** | Bitcoin Core `script_tests.json` | `BitcoinKernel` (SPM) |
| **TransactionVectorTests** | Bitcoin Core `tx_valid/invalid.json` | `BitcoinKernel` (SPM) |
| **BlockfilterVectorTests** | Bitcoin Core `blockfilters.json` | `BitcoinKernel` (SPM) |

### Shared Code

- **TestShared/** — `HexHelpers`, `VectorLoader` utilities (compiled into each vector test target)

## Architecture

All targets depend directly on SPM package products (`Bitcoin`, `BitcoinKernel`, `RPCModels`, `Tor`). No intermediate static framework wrappers — keeping the project simple and fast to build.

## Tor Integration

Both **NodeApp** and **KernelApp** embed Tor support via the [`swift-tor`](https://github.com/21-DOT-DEV/swift-tor) package.

### Dependency Setup

`swift-tor` is declared as a local path dependency in `Project.swift`:

```swift
packages: [
    .package(path: ".."),
    .package(path: "../../swift-tor"),
]
```

This requires `swift-tor` to be cloned as a sibling directory. It is **not** declared in the root `Package.swift` to avoid increasing resolution time for public consumers.

### Key Files

| File | Purpose |
|------|---------|
| `NodeApp/TorViewModel.swift` | Tor lifecycle management (`@Observable`, `@MainActor`) |
| `NodeApp/DaemonConfig.swift` | Type-safe `BitcoinConfig` argument builder with `torProxy:` parameter |
| `KernelApp/TorViewModel.swift` | Tor plumbing (copy of NodeApp's, networking deferred) |
| `NodeAppTests/TorViewModelTests.swift` | Unit tests for TorViewModel state logic |
| `NodeAppTests/TorIntegrationTests.swift` | Live Tor lifecycle test (`.disabled`, network required) |

### Tor Toggle Behavior

| Action | Result |
|--------|--------|
| Tor toggle ON | `TorClient` starts immediately with ephemeral SOCKS port; bootstrap progress shown |
| Tor toggle OFF | `TorClient` stops; state resets to disabled |
| Start Node (Tor ready) | Daemon launched with `-proxy=<host>:<port>` from live SOCKS endpoint |
| Start Node (Tor bootstrapping) | Start button disabled until Tor is ready |
| Stop Node | Daemon stops; Tor keeps running (user toggles Tor OFF to stop it) |
| Private Broadcast toggle | Adds `-privatebroadcast=1`; disabled when Tor is off |

### `DaemonConfig` API

`DaemonConfig.buildArguments(torProxy:)` builds daemon CLI arguments using the type-safe `BitcoinConfig` builder from the `Bitcoin` library:

```swift
// Without Tor
let args = DaemonConfig.buildArguments()

// With Tor (proxy address from TorViewModel)
let args = DaemonConfig.buildArguments(torProxy: torViewModel.proxyAddress)
```

When `torProxy` is `nil` and `tor_enabled` is true, the `-proxy=` argument is omitted (Tor not yet bootstrapped). When `tor_enabled` is false, the `torProxy` parameter is ignored.

### Manual Integration Testing

The Tor integration test is gated with `.disabled` to avoid network dependencies in CI. To run manually:

```bash
# Run Tor lifecycle test only
xcodebuild test -workspace Projects/Bitcoin.xcworkspace \
    -scheme Bitcoin-Workspace \
    -destination 'platform=macOS' \
    -only-testing:NodeAppTests/TorIntegrationTests
```

> **Note**: Tor bootstrap takes 30–60s (5–10s with cached consensus). The test has a 3-minute timeout.

### Entitlements

Both apps require `com.apple.security.network.client` for Tor SOCKS connections. NodeApp additionally has `com.apple.security.network.server` for the RPC listener.

## Configuration

Each target uses the **Shared/Debug/Release** xcconfig pattern:
- `Shared.xcconfig` — common settings (versioning, module verifier, security analyzers)
- `Debug.xcconfig` — `#include "Shared.xcconfig"` + debug overrides
- `Release.xcconfig` — `#include "Shared.xcconfig"` + release overrides

## Platforms

- **macOS 15.0** (primary development/testing)
- **iOS 18.0** (BitcoinKernel targets build; Bitcoin targets require macOS due to `sys/random.h`)
