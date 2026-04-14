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
| **NodeApp** | Full-node demo (RPC, Daemon) | `Bitcoin` |
| **KernelApp** | Kernel-only demo (chain types, validation) | `BitcoinKernel` |
| **XCFrameworkApp** | Multi-library demo (both modules) | `Bitcoin`, `BitcoinKernel` |

### Test Targets

| Target | Description | Dependencies |
|--------|-------------|-------------|
| **BitcoinTests** | Bitcoin library tests | `Bitcoin` (SPM) |
| **BitcoinKernelTests** | BitcoinKernel library tests | `BitcoinKernel` (SPM) |
| **NodeAppTests** | NodeApp UI/logic tests | `NodeApp` |
| **KernelAppTests** | KernelApp UI/logic tests | `KernelApp` |
| **RPCModelsTests** | RPC model decoding tests | `Bitcoin` (SPM) |
| **ScriptVectorTests** | Bitcoin Core `script_tests.json` | `BitcoinKernel` (SPM) |
| **TransactionVectorTests** | Bitcoin Core `tx_valid/invalid.json` | `BitcoinKernel` (SPM) |
| **BlockfilterVectorTests** | Bitcoin Core `blockfilters.json` | `BitcoinKernel` (SPM) |

### Shared Code

- **TestShared/** — `HexHelpers`, `VectorLoader` utilities (compiled into each vector test target)

## Architecture

All targets depend directly on SPM package products (`Bitcoin`, `BitcoinKernel`, `RPCModels`). No intermediate static framework wrappers — keeping the project simple and fast to build.

## Configuration

Each target uses the **Shared/Debug/Release** xcconfig pattern:
- `Shared.xcconfig` — common settings (versioning, module verifier, security analyzers)
- `Debug.xcconfig` — `#include "Shared.xcconfig"` + debug overrides
- `Release.xcconfig` — `#include "Shared.xcconfig"` + release overrides

## Platforms

- **macOS 15.0** (primary development/testing)
- **iOS 18.0** (BitcoinKernel targets build; Bitcoin targets require macOS due to `sys/random.h`)
