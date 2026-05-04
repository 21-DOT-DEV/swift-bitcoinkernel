//
//  KernelAppViewModel.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import BitcoinKernel
import Foundation
import Observation
import OSLog
import Tor

// MARK: - KernelAppViewModel

/// View-model orchestrating ``BitcoinKernel`` over a ``BlockSource``,
/// driven by ``KernelAppSettings``.
///
/// ### Responsibilities
///
/// - Owns the resident kernel via ``ResidentKernel``.
/// - Iterates ``BlockchainSync/updates()`` and translates each ``Update``
///   into ``snapshot``.
/// - Mediates settings changes that require kernel teardown via the
///   per-setting classifier in ``SettingsChangeKind``.
/// - Stays foreground/background-agnostic; ``progress`` is exposed for
///   later wiring to a system `BGContinuedProcessingTask`.
///
/// ### Test seams
///
/// The two factories (``KernelFactory`` and ``BlockSourceFactory``) are
/// dependency-injection points — production passes the default closures
/// that build real ``ResidentKernel`` and ``EsploraBlockSource`` values;
/// tests pass closures that build in-memory regtest kernels and
/// ``MockBlockSource`` instances.
@MainActor @Observable
final class KernelAppViewModel {

    // MARK: - Public surface

    /// UI-bindable observable snapshot. Updated on each
    /// ``BlockchainSync/Update`` from the running sync.
    private(set) var snapshot: SyncSnapshot = .idle

    /// Forwarded persistent ``Foundation/Progress`` from the active
    /// sync. Suitable for binding a system
    /// `BGContinuedProcessingTask.progress` once background-task support
    /// is wired in. Falls back to a fresh empty `Progress` when no run is
    /// active.
    var progress: Foundation.Progress {
        currentSync?.progress ?? Foundation.Progress()
    }

    /// The resident kernel — `nil` when stopped, present once
    /// ``start()`` has constructed it. Visible for testability;
    /// production callers should not depend on this.
    @ObservationIgnored private(set) var residentKernel: ResidentKernel?

    /// The current sync run's `Task`. `nil` when no run is active.
    /// Visible for testability so tests can `await syncTask?.value` to
    /// observe terminal state without polling.
    @ObservationIgnored private(set) var syncTask: Task<Void, Never>?

    /// Snapshot of ``settings`` captured at the end of the most recent
    /// successful `start()` / `requestReindex(_:)` / `applySettingsChange()`.
    /// Used by ``applySettingsChange()`` to diff against the live
    /// settings and decide the required action. `nil` while idle.
    @ObservationIgnored private(set) var lastAppliedSnapshot: KernelAppSettingsSnapshot?

    // MARK: - Dependencies

    /// Builds a ``ResidentKernel`` for a given chain/dir/threads/reindex.
    typealias KernelFactory = @Sendable (
        _ chainType: ChainType,
        _ dataDirectory: URL,
        _ workerThreads: Int32,
        _ reindex: ReindexMode?
    ) async throws -> ResidentKernel

    /// Builds a ``BlockSource`` from a configured endpoint URL and an
    /// optional SOCKS5 proxy endpoint. Production wiring builds an
    /// ``EsploraBlockSource`` whose underlying ``URLSession`` is either
    /// the shared default (no proxy) or one constructed via
    /// ``URLSessionConfiguration/ephemeralProxyConfigurationForTor(socksEndpoint:)``.
    /// Tests inject a closure that records the ``HostPort`` argument to
    /// verify proxy wiring without standing up a live SOCKS listener.
    typealias BlockSourceFactory = @Sendable (_ endpoint: URL, _ socks: HostPort?) -> any BlockSource

    @ObservationIgnored let settings: KernelAppSettings
    @ObservationIgnored let tor: TorViewModel
    @ObservationIgnored private let kernelFactory: KernelFactory
    @ObservationIgnored private let blockSourceFactory: BlockSourceFactory

    @ObservationIgnored private var currentSync: BlockchainSync?

    /// Observer task that waits for Tor to finish bootstrapping when
    /// the user has requested a Tor-routed sync. `nil` outside of the
    /// ``SyncSnapshot/Phase/waitingForTor`` window.
    @ObservationIgnored private var torWaitTask: Task<Void, Never>?

    @ObservationIgnored private static let logger = Logger(
        subsystem: "dev.21.KernelApp",
        category: "KernelAppViewModel"
    )

    // MARK: - Init

    init(
        settings: KernelAppSettings,
        tor: TorViewModel,
        kernelFactory: @escaping KernelFactory = KernelAppViewModel.defaultKernelFactory,
        blockSourceFactory: @escaping BlockSourceFactory = KernelAppViewModel.defaultBlockSourceFactory
    ) {
        self.settings = settings
        self.tor = tor
        self.kernelFactory = kernelFactory
        self.blockSourceFactory = blockSourceFactory
    }

    // MARK: - Lifecycle

    /// Open the kernel (if not already resident) and spawn the sync run.
    ///
    /// Foreground/background-agnostic — same path is taken whether
    /// invoked from a button tap or from a future
    /// `BGContinuedProcessingTask` resumption.
    func start() async {
        guard let endpoint = settings.blockSourceEndpoint else {
            snapshot = SyncSnapshot(
                phase: .failed("No block source selected"),
                statusText: "Select a block source to begin syncing",
                localHeight: 0,
                remoteHeight: 0,
                tipHash: Data(),
                verificationProgress: 0
            )
            return
        }

        // No-op if already running or waiting for Tor.
        if syncTask != nil || torWaitTask != nil { return }

        // If the user wants Tor routing but Tor isn't ready yet, enter
        // the waitingForTor state and kick the sync automatically once
        // bootstrap completes. The observer also forwards terminal
        // Tor failures into the snapshot so the user isn't left hanging.
        if settings.routeDownloadsThroughTor && !tor.isReady {
            enterWaitingForTor(endpoint: endpoint)
            return
        }

        await openKernelAndSpawn(endpoint: endpoint, reindex: nil)
    }

    /// Tear down the resident kernel and rebuild it with the requested
    /// wipe flags, then resume sync.
    ///
    /// Per-mode wipe flags pass through ``ResidentKernel/make`` →
    /// ``ChainstateManagerOptions/setWipeDBs(blockTreeDB:chainstateDB:)``.
    /// The kernel must be torn down because the wipe options are only
    /// consulted at construction time.
    func requestReindex(_ mode: ReindexMode) async {
        await stop()

        guard let endpoint = settings.blockSourceEndpoint else {
            // The endpoint went missing between user gesture and
            // execution — surface the same precondition failure as
            // start() would.
            snapshot = SyncSnapshot(
                phase: .failed("No block source selected"),
                statusText: "Select a block source to begin syncing",
                localHeight: 0,
                remoteHeight: 0,
                tipHash: Data(),
                verificationProgress: 0
            )
            return
        }

        // Symmetry with start(): a reindex requested while Tor isn't
        // ready waits for bootstrap before rebuilding the kernel.
        if settings.routeDownloadsThroughTor && !tor.isReady {
            enterWaitingForTor(endpoint: endpoint, reindex: mode)
            return
        }

        await openKernelAndSpawn(endpoint: endpoint, reindex: mode)
    }

    /// Reconcile the running kernel + sync with any changes to
    /// ``settings`` since the last apply.
    ///
    /// Classifies the diff via ``SettingsChangeKind/classify(previous:current:)``:
    ///
    /// - `.none` → no-op.
    /// - `.restartSync` → cancel and respawn the sync task against the
    ///   fresh block-source endpoint. The resident kernel is preserved.
    /// - `.restartKernel` → teardown the kernel, reopen against the new
    ///   settings, then respawn sync.
    ///
    /// No-ops if the view model has never been started (no baseline
    /// snapshot to diff against) — the next `start()` will pick up the
    /// current settings directly.
    func applySettingsChange() async {
        guard let previous = lastAppliedSnapshot else { return }
        let current = KernelAppSettingsSnapshot(settings: settings)
        let kind = SettingsChangeKind.classify(previous: previous, current: current)

        switch kind {
        case .none:
            return

        case .restartSync:
            // Preserve the kernel; just respawn sync against the new
            // source. Mirrors the endpoint precondition + Tor gating
            // in `start()`.
            guard let endpoint = settings.blockSourceEndpoint else {
                await cancelSyncTask()
                cancelTorWait()
                snapshot = SyncSnapshot(
                    phase: .failed("No block source selected"),
                    statusText: "Select a block source to begin syncing",
                    localHeight: 0,
                    remoteHeight: 0,
                    tipHash: Data(),
                    verificationProgress: 0
                )
                return
            }
            await cancelSyncTask()
            cancelTorWait()
            if settings.routeDownloadsThroughTor && !tor.isReady {
                enterWaitingForTor(endpoint: endpoint)
                return
            }
            spawnSyncTask(endpoint: endpoint, socks: currentSocksIfRouting())
            lastAppliedSnapshot = current

        case .restartKernel:
            // Full teardown + reopen. Same shape as `start()` but with
            // an explicit stop() first so the wipe-free rebuild is
            // unambiguous.
            await stop()
            await start()
            // `start()` refreshes `lastAppliedSnapshot` on success.
        }
    }

    /// Cancel the running sync task and tear down the resident kernel.
    ///
    /// Idempotent — safe to call from `expirationHandler`s, scene-phase
    /// transitions, and explicit user actions. Awaits the sync task so
    /// caller is guaranteed clean shutdown semantics.
    func stop() async {
        cancelTorWait()
        await cancelSyncTask()
        residentKernel = nil
        snapshot = .idle
        lastAppliedSnapshot = nil
    }

    // MARK: - Private

    /// Cancel the running sync task (if any) and clear ``currentSync``,
    /// leaving the resident kernel in place. Idempotent.
    private func cancelSyncTask() async {
        if let task = syncTask {
            task.cancel()
            await task.value
            syncTask = nil
        }
        currentSync = nil
    }

    /// Cancel any in-flight wait-for-Tor observer. Idempotent.
    private func cancelTorWait() {
        torWaitTask?.cancel()
        torWaitTask = nil
    }

    /// Build the kernel (if needed) and spawn the sync task against
    /// `endpoint`. Shared fast path between ``start()``,
    /// ``requestReindex(_:)``, and the Tor-wait observer's
    /// post-bootstrap callback.
    private func openKernelAndSpawn(endpoint: URL, reindex: ReindexMode?) async {
        // Reindex always rebuilds; plain start reuses the resident kernel
        // when present.
        let needsBuild = reindex != nil || residentKernel == nil
        if needsBuild {
            do {
                residentKernel = try await kernelFactory(
                    settings.chainType,
                    settings.effectiveDataDirectory,
                    settings.workerThreadCount,
                    reindex
                )
            } catch {
                Self.logger.error("kernel open failed: \(String(describing: error), privacy: .public)")
                snapshot = SyncSnapshot(
                    phase: .failed(error.localizedDescription),
                    statusText: reindex == nil ? "Kernel open failed" : "Reindex kernel open failed",
                    localHeight: 0,
                    remoteHeight: 0,
                    tipHash: Data(),
                    verificationProgress: 0
                )
                return
            }
        }

        spawnSyncTask(endpoint: endpoint, socks: currentSocksIfRouting())
        lastAppliedSnapshot = KernelAppSettingsSnapshot(settings: settings)
    }

    /// The live Tor SOCKS endpoint iff the user has opted into routing
    /// and Tor is ready. Otherwise `nil` — tells the block-source
    /// factory to build a direct-HTTPS session.
    private func currentSocksIfRouting() -> HostPort? {
        guard settings.routeDownloadsThroughTor, tor.isReady else { return nil }
        return tor.socksEndpoint
    }

    private func spawnSyncTask(endpoint: URL, socks: HostPort?) {
        guard let kernel = residentKernel else { return }
        let source = blockSourceFactory(endpoint, socks)
        let sync = kernel.makeSync(source: source)
        currentSync = sync

        syncTask = Task { [weak self] in
            for await update in sync.updates() {
                await self?.apply(update: update)
            }
            // Sequence ended — either terminal (.finished/.failed) was
            // already applied above, or the iterator was cancelled and
            // emitted nothing. In the latter case `stop()` is responsible
            // for the snapshot reset.
        }
    }

    private func apply(update: BlockchainSync.Update) {
        snapshot = SyncSnapshot(from: update)
    }

    // MARK: - Wait-for-Tor

    /// Enter the ``SyncSnapshot/Phase/waitingForTor`` state and park an
    /// observer on the shared ``TorViewModel``. When Tor reports
    /// ``TorViewModel/isReady`` the observer spawns the sync with the
    /// fresh SOCKS endpoint. When Tor lands in
    /// ``TorDisplayState/failed`` without a scheduled retry, the
    /// observer surfaces a terminal ``SyncSnapshot/Phase/failed(_:)``
    /// so the UI doesn't wait forever.
    ///
    /// Pre-condition: the caller has already validated
    /// `settings.blockSourceEndpoint != nil` and
    /// `settings.routeDownloadsThroughTor == true`.
    private func enterWaitingForTor(endpoint: URL, reindex: ReindexMode? = nil) {
        cancelTorWait()
        snapshot = SyncSnapshot(
            phase: .waitingForTor,
            statusText: torStatusText(),
            localHeight: 0,
            remoteHeight: 0,
            tipHash: Data(),
            verificationProgress: 0
        )

        torWaitTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.tor.isReady {
                    await self.openKernelAndSpawn(endpoint: endpoint, reindex: reindex)
                    self.torWaitTask = nil
                    return
                }
                if self.tor.displayState == .failed && self.tor.nextRetryAt == nil {
                    self.snapshot = SyncSnapshot(
                        phase: .failed("Tor bootstrap failed"),
                        statusText: "Tor could not start — tap retry in Settings or disable Tor routing",
                        localHeight: 0,
                        remoteHeight: 0,
                        tipHash: Data(),
                        verificationProgress: 0
                    )
                    self.torWaitTask = nil
                    return
                }
                // Refresh the statusText so the bootstrap percentage in
                // the UI stays in sync. TorViewModel publishes these
                // changes on the main actor; a short sleep is cheaper
                // and more portable than an Observation subscription
                // from a non-View context.
                self.snapshot.statusText = self.torStatusText()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// Human-readable status string for the ``waitingForTor`` snapshot.
    private func torStatusText() -> String {
        switch tor.displayState {
        case .disabled:
            return "Starting Tor…"
        case .starting:
            if tor.bootstrapProgress > 0 {
                return "Bootstrapping Tor… \(tor.bootstrapProgress)%"
            }
            return "Bootstrapping Tor…"
        case .running:
            return "Connecting through Tor…"
        case .stopping:
            return "Tor stopping — waiting to restart…"
        case .failed:
            return "Tor failed — retrying…"
        }
    }

    // MARK: - Default factories (production)

    @Sendable
    static func defaultKernelFactory(
        chainType: ChainType,
        dataDirectory: URL,
        workerThreads: Int32,
        reindex: ReindexMode?
    ) async throws -> ResidentKernel {
        try await ResidentKernel.make(
            chainType: chainType,
            dataDirectory: dataDirectory,
            workerThreads: workerThreads,
            reindex: reindex,
            inMemoryDatabases: false
        )
    }

    @Sendable
    static func defaultBlockSourceFactory(endpoint: URL, socks: HostPort?) -> any BlockSource {
        if let socks {
            let config = URLSessionConfiguration.ephemeralProxyConfigurationForTor(socksEndpoint: socks)
            return EsploraBlockSource(endpoint: endpoint, urlSession: URLSession(configuration: config))
        }
        return EsploraBlockSource(endpoint: endpoint)
    }
}
