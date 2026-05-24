# Chain Sync

@Metadata {
    @TitleHeading("How-to Guide")
}

Drive a ``ChainstateManager`` from an Esplora-compatible HTTP source with a typed `AsyncSequence` of progress snapshots and a `Foundation.Progress` hook for `SwiftUI.ProgressView` and iOS 26's `BGContinuedProcessingTask.progress`.

## Overview

> Warning: Mainnet initial block download is on the order of 600 GB and is not a practical target for mobile today. Signet (< 50 MB typical) is swift-bitcoinkernel's primary sync target; testnet and regtest are for development and testing.

``BlockchainSync`` is a value-type engine that walks a local chainstate from its current tip to the source's best tip, processing each block through ``ChainstateManager/processBlock(_:)`` and emitting typed ``BlockchainSync/Update`` snapshots. The API shape mirrors Apple's [`CLLocationUpdate.liveUpdates(_:)`](https://developer.apple.com/documentation/corelocation/cllocationupdate/liveupdates(_:)) — a configuration struct exposing a typed `Updates` sequence — while the vocabulary (``BlockTip``, ``BlockchainSync/Update/verificationProgress``, ``BlockchainSync/Update/State-swift.enum``) mirrors Bitcoin Core's [`interfaces::BlockTip`](https://github.com/bitcoin/bitcoin/blob/master/src/interfaces/node.h), [`GetVerificationProgress`](https://github.com/bitcoin/bitcoin/blob/master/src/validation.h), and [`SynchronizationState`](https://github.com/bitcoin/bitcoin/blob/master/src/validationinterface.h) so Bitcoin developers recognize it on sight.

The engine pairs a pluggable ``BlockSource`` (production: ``EsploraBlockSource`` over HTTP; test: your own conformer or an in-memory mock) with a single kernel ``Context``. Blocks flow hash-addressed per [LDK's BlockSource convention](https://docs.rs/lightning-block-sync/latest/lightning_block_sync/) — height-addressing is reserved for the resume fork-point check because height is a reorg hazard.

### Where to start

Run the code under **Running a sync** below against signet for a working end-to-end walkthrough. If you already have a ``ChainstateManager``, read **Observing progress** to bind `Foundation.Progress` to `SwiftUI.ProgressView` or iOS 26's `BGContinuedProcessingTask`. To implement a non-HTTP block source (P2P, peer-relay, a local Esplora fork), jump to **Implementing a custom block source** for the hash-addressed contract.

### Choosing a block source

swift-bitcoinkernel does not hard-code a default endpoint — the library ships URL convenience accessors for common public Esplora instances, and callers pick one explicitly. This matters: the block source is the network trust authority for validation input, and the library does not silently pick one for you.

```swift
import BitcoinKernel

// Signet is the recommended real-network sync target.
let source = EsploraBlockSource(endpoint: .mempoolSpaceSignet)
```

Shipped accessors: `URL.mempoolSpaceMainnet`, `URL.mempoolSpaceTestnet`, `URL.mempoolSpaceTestnet4`, `URL.mempoolSpaceSignet`, `URL.blockstreamInfo`, `URL.blockstreamInfoTestnet`. Implementing your own ``BlockSource`` (for P2P, a local Esplora, a peer relay, etc.) is covered further down.

### Running a sync

```swift
let params = ChainParameters(.signet)
let ctxOpts = ContextOptions()
ctxOpts.setChainParams(params)
let context = try Context(options: ctxOpts)

let mgrOpts = try ChainstateManagerOptions(context: context, dataDirectory: dataDir)
let manager = try ChainstateManager(options: mgrOpts)

let sync = BlockchainSync(
    manager: manager,
    source: EsploraBlockSource(endpoint: .mempoolSpaceSignet),
    context: context
)

for await update in sync.updates() {
    print("\(update.tip.height)/\(update.remoteTip.height) — \(update.state)")
}
```

The sequence starts with a ``BlockchainSync/Update/State-swift.enum/preparing`` update (remote not yet polled), transitions to ``BlockchainSync/Update/State-swift.enum/syncing`` for each validated block, and ends with a terminal ``BlockchainSync/Update/State-swift.enum/finished`` or ``BlockchainSync/Update/State-swift.enum/failed(_:)``. Cancel by breaking the `for await` loop or cancelling the enclosing `Task` — the iterator cleanup calls ``Context/interrupt()`` automatically.

### Observing progress

Two paths — pick whichever fits your UI framework. The [`Foundation.Progress`](https://developer.apple.com/documentation/foundation/progress) instance is KVO-observable and integrates natively with [`BGContinuedProcessingTask`](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask) (iOS 26+):

```swift
// Option A: read progress from each Update as it arrives.
for await update in sync.updates() {
    progressBar.progress = update.verificationProgress  // 0.0 … 1.0
}

// Option B: bind the Foundation.Progress to SwiftUI or BGContinuedProcessingTask.
Task { for await _ in sync.updates() {} }         // drain in background
ProgressView(sync.progress)                        // SwiftUI — KVO auto-updates
bgTask.progress = sync.progress                    // iOS 26+ BGContinuedProcessingTask
```

The same ``BlockchainSync/progress`` instance persists across ``BlockchainSync/updates()`` calls, so `BGContinuedProcessingTask.progress = sync.progress` wires once and keeps tracking even if you stop and resume the sequence.

### Handling errors

``BlockchainSync`` is non-throwing. Failures arrive as a terminal ``BlockchainSync/Update/State-swift.enum/failed(_:)`` element carrying a human-readable reason, matching the `CLLocationUpdate` precedent where errors encode as update state, not as thrown exceptions:

```swift
for await update in sync.updates() {
    if case .failed(let reason) = update.state {
        logger.error("Sync failed: \(reason)")
    }
}
```

| Condition | Reason substring |
|-----------|------------------|
| Source HTTP 404 | `fetching block at height N: … not found` |
| Source 429/5xx after retries exhausted | `HTTP 500 after N attempt(s)` |
| Local chain diverges from source | `remote chain diverges at height N — reindex required` |
| Local ahead of source (e.g. wrong network) | `remote is behind local …` |
| Kernel rejects block | `kernel rejected block at height N` |

Cancellation (`Task.cancel()` or `break` from the `for await` loop) ends the sequence silently — no final `.failed` is emitted, because user-initiated stop is a clean lifecycle event, not a failure.

### Implementing a custom block source

Conform to ``BlockSource``. All `Data` hashes crossing this protocol are in **internal (kernel) byte order** — 32 bytes, reversed from the display-order hex that block explorers show. Conformers speaking to external services (Esplora, P2P, etc.) are responsible for the byte-order translation at their boundary.

```swift
struct PeerBlockSource: BlockSource {
    func bestTip() async throws -> BlockTip              { /* … */ }
    func blockHash(atHeight height: Int) async throws -> Data   { /* … */ }
    func blockHeader(for hash: Data) async throws -> BlockHeader { /* … */ }
    func block(for hash: Data) async throws -> Block     { /* … */ }
}
```

Errors thrown from a conformer should be ``BlockSourceError`` — the engine maps those into terminal `.failed` updates with the localized description. A future `PeerBlockSource` built atop [swift-event's async TCP sockets](https://github.com/21-DOT-DEV/swift-event) would drop into the same ``BlockchainSync`` engine as ``EsploraBlockSource`` with no app-layer changes.

### Routing through Tor

``EsploraBlockSource`` accepts any `URLSession`. Configure one with a SOCKS5 proxy pointing at a local Tor listener (e.g., from [swift-tor](https://github.com/21-DOT-DEV/swift-tor)) to route every HTTP fetch through Tor:

```swift
let config = URLSessionConfiguration.ephemeral
config.connectionProxyDictionary = [
    kCFStreamPropertySOCKSProxyHost as String: "127.0.0.1",
    kCFStreamPropertySOCKSProxyPort as String: 9150,
    kCFStreamPropertySOCKSVersion  as String: kCFStreamSocketSOCKSVersion5,
]
let session = URLSession(configuration: config)

let source = EsploraBlockSource(
    endpoint: .mempoolSpaceSignet,
    urlSession: session
)
```

All block-tip queries, block fetches, header fetches, retry attempts, and `Retry-After`-paced waits transparently route through Tor. Application-level integration (bootstrap UI, settings toggles, lifecycle) is out of scope here — that ships as part of the forthcoming `KernelApp` demo.

### State-enum disambiguation

``BlockchainSync/Update/State-swift.enum`` is the sync engine's own lifecycle enum: `preparing | syncing | finished | failed(String)`. It is **distinct from** ``SynchronizationState``, which is the kernel C callback enum (`initReindex`, `initDownload`, `postInit`) passed to ``NotificationCallbacks/blockTip``. They solve different problems:

- ``BlockchainSync/Update/State-swift.enum`` — your application's view of the sync session.
- ``SynchronizationState`` — Bitcoin Core's view of where validation currently sits in its startup/IBD state machine.

Most application code should consume ``BlockchainSync/Update/State-swift.enum`` from the sequence and leave ``SynchronizationState`` to kernel-callback consumers.

### Pre-1.0 API stability

swift-bitcoinkernel is pre-1.0 — major-version zero per [SemVer 2.0 §4](https://semver.org/#spec-item-4). ``BlockSource``, ``BlockchainSync``, ``BlockTip``, ``BlockSourceError``, and the `URL` convenience accessors may change across `0.y.z` releases until the first 1.0 tag. Pin an exact version in `Package.swift` to avoid surprise migrations:

```swift
.package(url: "https://github.com/21-DOT-DEV/swift-bitcoinkernel.git", exact: "0.x.y")
```

## See Also

- <doc:GettingStarted>
- <doc:ValidatingBlocks>
- ``BlockchainSync``
- ``EsploraBlockSource``
