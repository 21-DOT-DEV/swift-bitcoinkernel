//
//  TorViewModel.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2022-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import Observation
import os.log
import Tor

// MARK: - TorDisplayState

/// Display state for the Tor toggle UI.
///
/// Maps `TorClient`'s internal state + bootstrap status to user-facing states.
/// `.running` means fully bootstrapped and ready for proxy use — not just
/// that the Tor process is alive.
enum TorDisplayState: String, Sendable {
    case disabled = "Disabled"
    case starting = "Starting"
    case running  = "Running"
    case stopping = "Stopping"
    case failed   = "Failed"
}

// MARK: - TorViewModel

/// Observable view model bridging ``TorClient`` (from swift-tor) into
/// SwiftUI views in both NodeApp and KernelApp.
///
/// Responsibilities:
/// - Maps the async ``TorSession`` lifecycle onto a synchronous display
///   state suitable for SwiftUI bindings.
/// - Handles rapid toggle OFF→ON races via a pending-restart queue.
/// - Provides bounded automatic retry (3 attempts, schedule `5s → 30s → 2min`)
///   followed by a user-invokable ``retry()`` on give-up.
/// - Tracks a `sessionID` UUID per start so consumers (NodeViewModel) can
///   detect Tor restarts and surface "restart required" hints.
@MainActor @Observable
final class TorViewModel {

    // MARK: - Observable display state

    var displayState: TorDisplayState = .disabled
    var bootstrapProgress: Int = 0
    var bootstrapSummary: String = ""
    private(set) var socksEndpoint: HostPort?

    /// Unique identifier of the current Tor session. Regenerated on every
    /// successful `performStart()`, cleared on `.disabled` / `.failed`.
    ///
    /// Used by `NodeViewModel.launchedWithTorSession` to detect Tor
    /// restarts (which invalidate the daemon's running `-proxy=` port).
    private(set) var sessionID: UUID?

    /// Count of consecutive failed bootstrap attempts since the last
    /// transition to `.disabled` or `.running`. Drives the backoff schedule.
    private(set) var failureCount: Int = 0

    /// Wall-clock time when the next auto-retry is scheduled to fire.
    /// `nil` when no retry is scheduled (either pre-failure or exhausted).
    private(set) var nextRetryAt: Date?

    /// Whether Tor is fully bootstrapped and the SOCKS endpoint is available.
    var isReady: Bool { displayState == .running && socksEndpoint != nil }

    /// SOCKS proxy address in `host:port` format, suitable for `BitcoinConfig.proxy()`.
    var proxyAddress: String? { socksEndpoint?.description }

    /// Total attempts (initial + all scheduled retries) before the view model
    /// gives up and waits for a manual `retry()`. Exposed for the retry
    /// countdown UI which renders `"attempt X of Y"`.
    var maxAttempts: Int { backoffSchedule.count + 1 }

    // MARK: - Private state

    private let logger: Logger
    private let backoffSchedule: [Duration]
    private let makeSession: @Sendable (TorConfiguration) -> any TorSession

    /// Clock driving the auto-retry backoff. Defaults to `ContinuousClock`;
    /// tests inject a `TestClock` to advance backoff deterministically rather
    /// than waiting real time (Point-Free swift-clocks). Production code uses
    /// only the stdlib `Clock` protocol, so swift-clocks stays a test dependency.
    private let clock: any Clock<Duration>

    private var session: (any TorSession)?
    private var startTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var pendingStartAfterStop = false

    /// Monotonically-increasing count of successful `performStart()` calls.
    /// Stamped into `NodeDiagnostics` tags so snapshots diff cleanly across
    /// Tor restart cycles (e.g. user toggles off/on, or rapid stop-then-start).
    private var torStartRunCounter = 0

    // MARK: - Init

    /// Creates a Tor view model.
    ///
    /// - Parameters:
    ///   - subsystem: `os.log` subsystem tag. Pass the app's bundle id.
    ///   - backoffSchedule: Delays between automatic retries after a failed
    ///     bootstrap. After the schedule is exhausted the view model stays
    ///     in `.failed` until ``retry()`` or ``stop()`` is called. Must be
    ///     non-empty. Defaults to `[5s, 30s, 120s]`.
    ///   - makeSession: Factory that builds a `TorSession` from a config.
    ///     Defaults to the real `TorClient`. Tests inject a blocking double.
    init(
        subsystem: String = "dev.21.Bitcoin",
        backoffSchedule: [Duration] = [.seconds(5), .seconds(30), .seconds(120)],
        clock: any Clock<Duration> = ContinuousClock(),
        makeSession: @escaping @Sendable (TorConfiguration) -> any TorSession = { TorClient(configuration: $0) }
    ) {
        precondition(!backoffSchedule.isEmpty, "backoffSchedule must contain at least one delay")
        self.logger = Logger(subsystem: subsystem, category: "Tor")
        self.backoffSchedule = backoffSchedule
        self.clock = clock
        self.makeSession = makeSession
    }

    // MARK: - Lifecycle

    /// Request Tor to start.
    ///
    /// Behavior by current state:
    /// - `.disabled` / `.failed` (no pending retry): begin bootstrap immediately.
    /// - `.stopping`: queue a restart for when shutdown completes.
    /// - `.failed` with a pending retry: no-op (let the scheduled retry fire).
    /// - `.starting` / `.running`: no-op.
    func start() {
        // 1. Mid-stop: queue restart for when the stop task finishes.
        if displayState == .stopping {
            pendingStartAfterStop = true
            return
        }
        // 2. Already active.
        guard displayState == .disabled || displayState == .failed else { return }
        // 3. .failed with a scheduled retry: let the retry fire.
        if retryTask != nil { return }
        // 4. Clean state: proceed.
        performStart()
    }

    /// User-initiated retry after the automatic backoff schedule is exhausted.
    ///
    /// Resets the failure counter and immediately begins a fresh bootstrap.
    /// Safe to call from the "Tap to retry" UI affordance.
    func retry() {
        guard displayState == .failed, retryTask == nil else { return }
        failureCount = 0
        nextRetryAt = nil
        performStart()
    }

    /// Stop Tor (if running or starting) and release the session.
    ///
    /// Idempotent and race-safe: a second call during `.stopping` cancels
    /// any queued restart; a call from `.failed` clears retry state.
    func stop() {
        // Rapid OFF during mid-stop: cancel any queued restart.
        if displayState == .stopping {
            pendingStartAfterStop = false
            return
        }
        guard displayState == .running || displayState == .starting || displayState == .failed else {
            return
        }

        let run = torStartRunCounter
        NodeDiagnostics.snapshot("before-tor-stop-\(run)")

        pendingStartAfterStop = false
        retryTask?.cancel(); retryTask = nil
        startTask?.cancel(); startTask = nil
        eventTask?.cancel(); eventTask = nil

        let prevState = displayState
        displayState = .stopping
        nextRetryAt = nil

        let session = self.session
        self.session = nil

        // If we were .failed after give-up and no session is alive, skip
        // the async teardown — we'd just no-op in the Task.
        if session == nil && prevState == .failed {
            failureCount = 0
            socksEndpoint = nil
            bootstrapProgress = 0
            bootstrapSummary = ""
            sessionID = nil
            displayState = .disabled
            NodeDiagnostics.snapshot("after-tor-stop-\(run)")
            return
        }

        let logger = self.logger
        stopTask = Task { [weak self] in
            if let session { await session.stop() }
            await MainActor.run {
                guard let self else { return }
                self.socksEndpoint = nil
                self.bootstrapProgress = 0
                self.bootstrapSummary = ""
                self.sessionID = nil
                self.failureCount = 0
                self.displayState = .disabled
                self.stopTask = nil
                NodeDiagnostics.snapshot("after-tor-stop-\(run)")
                if self.pendingStartAfterStop {
                    self.pendingStartAfterStop = false
                    self.start()
                }
            }
            logger.info("Tor stopped")
        }
    }

    /// Waits until Tor is fully bootstrapped.
    ///
    /// Used by the node start flow to block until the proxy is available.
    func waitUntilReady() async {
        while !isReady && displayState == .starting {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    // MARK: - Private

    /// Kick off a fresh Tor bootstrap. Assumes the caller has already
    /// verified the state machine is in a startable position.
    ///
    /// Sentinel: bails if `displayState == .stopping`. This is the authoritative
    /// backstop for the retry-vs-stop race (Finding A round-2 review) — a
    /// scheduled retry whose `MainActor.run` body races past `stop()`'s
    /// `retryTask?.cancel()` would otherwise stomp `.stopping` → `.starting`
    /// and spawn an orphan session. Every production caller already avoids
    /// `.stopping`; this guard proves it at the one place that matters.
    private func performStart() {
        guard displayState != .stopping else {
            logger.debug("performStart suppressed: already stopping")
            return
        }
        torStartRunCounter += 1
        let run = torStartRunCounter
        NodeDiagnostics.snapshot("before-tor-start-\(run)")

        // Defensive: clean up any lingering session (e.g. from a prior
        // failed attempt whose catch block set session = nil but couldn't
        // reach the old instance to call stop on it).
        if let old = session {
            Task { await old.stop() }
            session = nil
        }

        retryTask?.cancel(); retryTask = nil
        nextRetryAt = nil

        displayState = .starting
        bootstrapProgress = 0
        bootstrapSummary = ""
        socksEndpoint = nil
        sessionID = UUID()

        let logger = self.logger
        let session = makeSession(
            TorConfiguration.ephemeral(cacheDirectory: Self.cacheDirectory)
        )
        self.session = session

        // `TorClient.events` is an async getter that registers a fresh
        // continuation per call. Between this synchronous `self.session =
        // session` and observeEvents()'s first `await` completing the
        // registration, the producer may broadcast up to a couple of
        // `.bootstrap` / `.stateChanged` events we never observe.
        // Harmless in practice: bootstrap progress is emitted continuously
        // (1%, 5%, …, 100%) so any single missed event is imperceptible,
        // and `.stateChanged(.starting)` is UI polish only. The authoritative
        // "bootstrapped" signal is the `try await session.waitUntilBootstrapped()`
        // call in the start Task, not the event stream (Finding G round-2).
        observeEvents(from: session)

        startTask = Task { [weak self] in
            do {
                try await session.start()
                guard !Task.isCancelled else { return }
                logger.info("Tor started, waiting for bootstrap…")

                try await session.waitUntilBootstrapped()
                guard !Task.isCancelled else { return }

                let endpoint = await session.socksEndpoint
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard let self, !Task.isCancelled else { return }
                    self.socksEndpoint = endpoint
                    self.bootstrapProgress = 100
                    self.failureCount = 0
                    self.displayState = .running
                    NodeDiagnostics.snapshot("after-tor-start-\(run)")
                    NodeDiagnostics.probeSocks5(
                        port: endpoint.map { UInt16(clamping: $0.port) },
                        tag: "after-tor-start-\(run)"
                    )
                }
                logger.info("Tor bootstrapped — SOCKS: \(endpoint?.description ?? "nil")")
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Tor start failed: \(error.localizedDescription)")
                // Release the dead session before transitioning — prevents
                // orphaned Tor threads on repeated re-entry from .failed.
                await session.stop()
                await MainActor.run {
                    guard let self, !Task.isCancelled else { return }
                    self.session = nil
                    self.sessionID = nil
                    self.handleFailure(error)
                }
            }
        }
    }

    /// Transition to `.failed` and schedule the next retry (or give up).
    private func handleFailure(_ error: Error) {
        failureCount += 1
        bootstrapSummary = error.localizedDescription
        displayState = .failed

        guard failureCount <= backoffSchedule.count else {
            // Exhausted the schedule — wait for user to tap retry or toggle off.
            nextRetryAt = nil
            retryTask = nil
            logger.warning("Tor retry schedule exhausted (\(self.failureCount) attempts)")
            return
        }

        let delay = backoffSchedule[failureCount - 1]
        let delaySeconds = durationSeconds(delay)
        nextRetryAt = Date().addingTimeInterval(delaySeconds)
        logger.info("Scheduling Tor retry #\(self.failureCount) in \(Int(delaySeconds))s")

        let clock = self.clock
        retryTask = Task { [weak self] in
            try? await clock.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                // Re-check cancellation INSIDE the actor hop — `stop()` may
                // have run between the pre-hop guard and here, cancelling
                // the task. Without this guard, a scheduled retry can spawn
                // a fresh session after shutdown has begun (Finding A).
                guard let self, !Task.isCancelled else { return }
                self.retryTask = nil
                self.nextRetryAt = nil
                self.performStart()
            }
        }
    }

    private func observeEvents(from session: any TorSession) {
        eventTask?.cancel()
        let logger = self.logger
        eventTask = Task { [weak self] in
            let stream = await session.events
            for await event in stream {
                guard !Task.isCancelled else { break }
                switch event {
                case .bootstrap(let progress, _, let summary):
                    await MainActor.run {
                        guard let self, !Task.isCancelled else { return }
                        self.bootstrapProgress = progress
                        self.bootstrapSummary = summary
                    }
                    logger.debug("Bootstrap: \(progress)% — \(summary)")
                case .stateChanged(let state):
                    logger.debug("Tor state: \(String(describing: state))")
                default:
                    break
                }
            }
        }
    }

    /// Best-effort conversion of a `Duration` to seconds for `Date` math.
    private func durationSeconds(_ d: Duration) -> TimeInterval {
        let comps = d.components
        return TimeInterval(comps.seconds) + TimeInterval(comps.attoseconds) / 1e18
    }

    /// Persistent cache directory for Tor consensus data.
    ///
    /// Reusing cached consensus across runs reduces bootstrap from ~40s to ~5–10s.
    private static var cacheDirectory: String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("tor-cache")

        try? FileManager.default.createDirectory(
            at: appSupport, withIntermediateDirectories: true
        )

        return appSupport.path
    }

    // MARK: - Testing hooks

    #if DEBUG
    /// Test hook: sets `displayState = .stopping` and invokes `performStart()`
    /// to verify the sentinel at the top of `performStart` correctly no-ops.
    ///
    /// Available only in DEBUG builds. Production call sites (`start`, `retry`,
    /// retry-task) never reach `performStart` from `.stopping` because of their
    /// own state guards; this hook exercises the final backstop in isolation.
    internal func _testPerformStartSuppressedDuringStop() {
        displayState = .stopping
        performStart()
    }

    /// Test hook: awaits the in-flight start attempt to finish. On return the
    /// terminal transition (`.running`, or `.failed` + retry scheduling) has been
    /// applied, so a test can assert the settled state with no polling. Combined
    /// with an injected `TestClock`, this drives the retry cascade deterministically:
    /// `clock.advance(by:)` fires the next attempt, then `awaitSettled()` waits for it.
    internal func awaitSettled() async {
        await startTask?.value
    }

    /// Test hook: awaits the in-flight stop teardown. Returns immediately when
    /// there is no async teardown (the give-up `.failed` path sets `.disabled`
    /// synchronously and spawns no task), so tests can assert post-stop state
    /// without polling.
    internal func awaitStopped() async {
        await stopTask?.value
    }
    #endif
}
