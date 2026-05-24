# Bitcoin Tuist Workspace

A Tuist-managed Xcode workspace with two demo apps (`NodeApp`, `KernelApp`) and their UI/logic test bundles, layered on top of the SPM package. Use this directory when you want to **see swift-bitcoinkernel running** — the SPM package itself is the thing to depend on; this workspace exists for hands-on exploration.

## Quick Start

```bash
# Generate the Xcode workspace
swift package --disable-sandbox tuist generate -p Projects/ --no-open

# Open it
open Projects/Bitcoin.xcworkspace
```

Then pick a scheme (`NodeApp` or `KernelApp`) and ⌘R.

## What's in here

### Demo apps

| App | What it demonstrates | Run |
|---|---|---|
| **NodeApp** | Embedded `bitcoind` lifecycle, RPC client, optional Tor SOCKS proxy, `BitcoinConfig` builder | `tuist build NodeApp -p Projects/ --platform macos` |
| **KernelApp** | `BitcoinKernel` chain sync via `BlockchainSync` over `EsploraBlockSource`, with optional Tor-routed block downloads | `tuist build KernelApp -p Projects/ --platform macos` |

> [!NOTE]
> Tuist commands run via the SwiftPM plugin: prefix with `swift package --disable-sandbox`. The plugin matches what CI invokes, so reproducing CI failures locally is `tuist build <Target> -p Projects/`.

### App test bundles (Tuist)

- **NodeAppTests** — UI/logic tests for `NodeApp`, including `TorViewModelTests` (state-machine, no network) and `TorIntegrationTests` (live Tor lifecycle, `.disabled` by default).
- **KernelAppTests** — UI/logic tests for `KernelApp`.

### SPM test targets (run alongside, not part of the Tuist workspace)

The package's own tests live under `Tests/` and are run with `swift test` from the repository root:

- **BitcoinTests** — Bitcoin library tests (`Bitcoin` target), including RPC model decode tests with fixture vectors under `Tests/BitcoinTests/Fixtures/`.
- **BitcoinKernelTests** — `BitcoinKernel` target tests.

### Run everything (apps + their bundles) via Tuist

```bash
swift package --disable-sandbox tuist test Bitcoin-Workspace -p Projects/ --platform macos
```

Or fall back to `xcodebuild` when you need finer-grained control:

```bash
xcodebuild test \
    -workspace Projects/Bitcoin.xcworkspace \
    -scheme NodeAppTests \
    -destination 'platform=macOS'
```

## Platforms

Both apps declare `destinations: [.iPhone, .iPad, .mac]` in `Project.swift` and have iOS-specific UI paths in their sources.

- **macOS 15+** — primary; everything builds and runs.
- **iOS 18+** — both apps target it. Day-to-day development and CI run on macOS; iOS builds are not exercised on every change, so treat them as best-effort until covered by a job in `.github/workflows/`.

## Going deeper

For Tor wiring, the `DaemonConfig` builder, integration-test recipes, entitlements, and the Shared/Debug/Release xcconfig pattern, see [`Projects/AGENTS.md`](AGENTS.md). For project-wide architecture and the subtree extraction flow, see the root [`AGENTS.md`](../AGENTS.md).
