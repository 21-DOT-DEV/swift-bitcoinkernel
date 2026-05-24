//
//  BlockchainSync.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Drives a ``ChainstateManager`` from a ``BlockSource`` toward the source's
/// tip, emitting typed progress updates as blocks are validated.
///
/// Shape follows Apple's `CLLocationUpdate.liveUpdates(_:)` pattern — a
/// value-type configuration exposing a typed `AsyncSequence` of progress
/// snapshots. Cancel by breaking the `for await` loop or cancelling the
/// enclosing `Task`; the iterator's cleanup calls ``Context/interrupt()``.
///
/// ```swift
/// let sync = BlockchainSync(manager: manager, source: source, context: context)
/// for await update in sync.updates() {
///     print("\(update.tip.height)/\(update.remoteTip.height) — \(update.state)")
/// }
/// ```
///
/// ### Error delivery
///
/// Failures arrive as `Update(state: .failed(reason), ...)` final elements;
/// the sequence is non-throwing. Cancellation ends the sequence silently
/// (no final Update — cancel is a clean lifecycle event, not a failure).
///
/// ### Concurrency
///
/// The sync loop runs on a background `Task` owned by the sequence iterator.
/// Block processing (`ChainstateManager.processBlock`) runs inline — fast
/// for regtest/signet, slow-but-acceptable for mainnet IBD. UI consumers
/// observe progress either through this sequence or ``progress`` (a
/// `Foundation.Progress` bound to the same state for `SwiftUI.ProgressView`
/// and `BGContinuedProcessingTask.progress` integration).
public struct BlockchainSync: Sendable {
    private let storage: SyncStorage

    /// Create a new sync engine.
    ///
    /// The engine is a value-type configuration: constructing one does no
    /// work. The sync loop starts on the first call to ``updates()``.
    ///
    /// - Parameters:
    ///   - manager: The kernel chainstate that will be advanced. Must be
    ///     configured with the same ``ChainType`` the `source` is reporting
    ///     on — validating signet blocks against a mainnet chainstate will
    ///     surface as rejections in ``Update/State-swift.enum/failed(_:)``.
    ///   - source: The block source providing remote chain data. Any
    ///     ``BlockSource`` conformer — HTTP (``EsploraBlockSource``), a
    ///     test mock, or a future P2P conformer — works identically.
    ///   - context: The kernel context used to interrupt long-running
    ///     ``ChainstateManager/processBlock(_:)`` calls on cancel.
    public init(manager: ChainstateManager, source: any BlockSource, context: Context) {
        self.storage = SyncStorage(manager: manager, source: source, context: context)
    }

    /// [`Foundation.Progress`](https://developer.apple.com/documentation/foundation/progress)
    /// tracking `completedUnitCount` = local tip height and `totalUnitCount`
    /// = remote tip height.
    ///
    /// The same `Progress` instance persists across ``updates()`` calls and
    /// survives the entire lifetime of this `BlockchainSync`. That
    /// persistence is the point: bind it once to
    /// `SwiftUI.ProgressView(_:)` or
    /// [`BGContinuedProcessingTask.progress`](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask/progress)
    /// and it tracks automatically, including across sync restarts.
    ///
    /// - Note: `Progress` updates use KVO; SwiftUI observes them without any
    ///   extra wiring. Raw KVO observers should key-path-observe
    ///   `fractionCompleted`.
    public var progress: Progress { storage.progress }

    /// Starts the sync and returns a typed async sequence of progress
    /// snapshots.
    ///
    /// Each call to `updates()` starts a fresh sync run — a `Task` spawns
    /// to drive the state machine. To stop a run, break the `for await`
    /// loop or cancel the enclosing `Task`; the iterator's cleanup (via
    /// `AsyncStream.onTermination`) calls ``Context/interrupt()`` to
    /// unblock any in-flight kernel processing.
    ///
    /// - Returns: A single-consumer ``Updates`` sequence. Iterating the
    ///   same sequence concurrently is undefined behavior — call
    ///   `updates()` again for a second consumer.
    public func updates() -> Updates {
        Updates(storage: storage)
    }

    /// A single-consumer `AsyncSequence` of ``Update`` values emitted as
    /// the sync engine drives the chainstate forward.
    ///
    /// Backed by an [`AsyncStream`](https://developer.apple.com/documentation/swift/asyncstream)
    /// with `.bufferingNewest(64)` — under a slow consumer, mid-sync updates
    /// may be dropped, but the initial ``Update/State-swift.enum/preparing``
    /// and the terminal ``Update/State-swift.enum/finished`` /
    /// ``Update/State-swift.enum/failed(_:)`` are always delivered.
    ///
    /// - Note: Iterating the same `Updates` value twice starts an independent
    ///   sync run on each iteration. That's rarely what you want; store a
    ///   single `Updates` value and iterate it once.
    public struct Updates: AsyncSequence, Sendable {
        public typealias Element = Update

        private let storage: SyncStorage

        init(storage: SyncStorage) {
            self.storage = storage
        }

        /// Create a new iterator — and implicitly a new sync run.
        ///
        /// Called by `for await` under the hood; you rarely call this
        /// directly. Each invocation launches a fresh background `Task`
        /// that runs the sync state machine.
        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(storage: storage)
        }

        /// Single-consumer iterator over a running sync.
        ///
        /// Owns the `AsyncStream` backing the sync and the `Task` that
        /// drives the producer. Cleanup (`Task.cancel()` +
        /// ``Context/interrupt()``) fires via `AsyncStream.onTermination`
        /// when the iterator goes out of scope or the stream finishes.
        public struct AsyncIterator: AsyncIteratorProtocol {
            private var streamIterator: AsyncStream<Update>.Iterator

            init(storage: SyncStorage) {
                let context = storage.context
                let stream = AsyncStream<Update>(bufferingPolicy: .bufferingNewest(64)) { continuation in
                    let task = Task {
                        await runSyncLoop(storage: storage, continuation: continuation)
                    }
                    continuation.onTermination = { @Sendable _ in
                        task.cancel()
                        _ = context.interrupt()
                    }
                }
                self.streamIterator = stream.makeAsyncIterator()
            }

            public mutating func next() async -> Update? {
                await streamIterator.next()
            }
        }
    }

    /// A single snapshot of sync progress — the element type emitted by
    /// ``Updates``.
    ///
    /// Each `Update` captures the sync engine's state at one moment:
    /// lifecycle phase, local chainstate tip, and the source's best tip as
    /// of the most recent ``BlockSource/bestTip()`` call.
    public struct Update: Sendable, Equatable {
        /// Lifecycle phase of a sync run. Mirrors Bitcoin Core's
        /// [`SynchronizationState`](https://github.com/bitcoin/bitcoin/blob/master/src/validationinterface.h)
        /// conceptually while remaining a distinct Swift type — see
        /// <doc:Sync#State-enum-disambiguation>.
        ///
        /// A sync run produces exactly one emission per state transition:
        /// exactly one ``preparing``, zero or more ``syncing``, and exactly
        /// one of ``finished`` or ``failed(_:)``. Cancellation produces no
        /// final emission at all — the sequence ends silently.
        public enum State: Sendable, Equatable {
            /// Initializing — resolving the remote tip, computing the fork
            /// point if resuming from non-genesis. Always the first emitted
            /// state; if it's also the last, the source or fork-point
            /// check failed before any blocks were fetched.
            case preparing

            /// Actively fetching and validating blocks. Emitted once per
            /// successfully validated block — ``tip`` advances monotonically,
            /// ``remoteTip`` advances whenever a re-poll catches source-side
            /// growth.
            case syncing

            /// Local chain has reached the source's tip. Terminal state —
            /// the sequence finishes after emitting this.
            case finished

            /// Sync stopped due to an error. The associated `String` is a
            /// human-readable reason for UI / logs (e.g.,
            /// `"fetching block at height 523: … not found"`). Terminal.
            ///
            /// Errors caught from a ``BlockSource`` conformer are wrapped
            /// with the operation context before reaching this case; raw
            /// error values are not preserved here. Catch ``BlockSourceError``
            /// at the source itself if you need typed handling.
            case failed(String)

            /// `true` for terminal states (``finished``, ``failed(_:)``) —
            /// after which the sequence will emit no further ``Update``s.
            ///
            /// Convenience for UI code that wants to disable a Stop button
            /// or switch to a "done" indicator:
            ///
            /// ```swift
            /// if update.state.isTerminal { stopButton.isEnabled = false }
            /// ```
            public var isTerminal: Bool {
                switch self {
                case .preparing, .syncing: return false
                case .finished, .failed: return true
                }
            }
        }

        /// Current lifecycle phase.
        public let state: State

        /// The local chainstate's best block at the moment this ``Update``
        /// was emitted.
        ///
        /// Advances monotonically within a single sync run: every
        /// ``State-swift.enum/syncing`` emission has `tip.height` strictly
        /// greater than the previous one's. During ``State-swift.enum/preparing``
        /// and terminal states, `tip` reflects whatever the chainstate read
        /// at that moment — including height 0 if the chainstate is fresh.
        public let tip: BlockTip

        /// The source's best block as of the most recent
        /// ``BlockSource/bestTip()`` call.
        ///
        /// Not monotonic within a sync run: the sync engine re-polls the
        /// source each time `tip.height` catches up to `remoteTip.height`,
        /// and if the source has advanced, `remoteTip` jumps forward.
        /// During the initial ``State-swift.enum/preparing`` emission — before
        /// the first `bestTip()` call succeeds — `remoteTip` is a placeholder
        /// with `height == 0`.
        public let remoteTip: BlockTip

        /// Creates an ``Update``.
        ///
        /// Public so ``BlockSource`` conformers and tests can construct
        /// synthetic updates; production code receives Updates from
        /// ``BlockchainSync/updates()``.
        ///
        /// - Parameters:
        ///   - state: The lifecycle phase this Update represents.
        ///   - tip: The local chainstate's best block.
        ///   - remoteTip: The source's best block as of the last poll.
        public init(state: State, tip: BlockTip, remoteTip: BlockTip) {
            self.state = state
            self.tip = tip
            self.remoteTip = remoteTip
        }

        /// Fraction of the remote chain validated locally, in `0.0...1.0`.
        ///
        /// Mirrors Bitcoin Core's
        /// [`GetVerificationProgress`](https://github.com/bitcoin/bitcoin/blob/master/src/validation.h)
        /// conceptually, using a simple `localHeight / remoteHeight` ratio.
        /// The time-weighted refinement Bitcoin Core uses — accounting for
        /// variable average block time — is reserved for potential future
        /// improvement.
        ///
        /// - Returns: `0.0` when remote height is unknown (initial
        ///   ``State-swift.enum/preparing``); `1.0` when local has reached
        ///   or exceeds remote (terminal ``State-swift.enum/finished`` or
        ///   transient reorg where local briefly sits ahead); otherwise the
        ///   clamped ratio.
        public var verificationProgress: Double {
            guard remoteTip.height > 0 else { return 0.0 }
            let ratio = Double(tip.height) / Double(remoteTip.height)
            return min(max(ratio, 0.0), 1.0)
        }
    }
}
