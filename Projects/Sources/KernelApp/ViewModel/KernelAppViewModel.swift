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

// MARK: - KernelAppViewModel

/// View-model orchestrating ``BitcoinKernel`` over a ``BlockSource``,
/// driven by ``KernelAppSettings``.
///
/// ### Responsibilities
///
/// - Owns the resident kernel (Q1: hybrid resident — see ``ResidentKernel``).
/// - Iterates ``BlockchainSync/updates()`` and translates each ``Update``
///   into ``snapshot`` (Q3: snapshot + Progress).
/// - Mediates settings changes that require kernel teardown (Q6:
///   per-setting policy).
/// - Stays foreground/background-agnostic; B4 binds ``progress`` to the
///   `BGContinuedProcessingTask` (Q7).
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
    /// sync. Used by Phase B4 to bind the system
    /// `BGContinuedProcessingTask.progress`. Falls back to a fresh
    /// empty `Progress` when no run is active.
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

    /// Builds a ``BlockSource`` from a configured endpoint URL.
    typealias BlockSourceFactory = @Sendable (URL) -> any BlockSource

    @ObservationIgnored let settings: KernelAppSettings
    @ObservationIgnored private let kernelFactory: KernelFactory
    @ObservationIgnored private let blockSourceFactory: BlockSourceFactory

    @ObservationIgnored private var currentSync: BlockchainSync?

    @ObservationIgnored private static let logger = Logger(
        subsystem: "dev.21.KernelApp",
        category: "KernelAppViewModel"
    )

    // MARK: - Init

    init(
        settings: KernelAppSettings,
        kernelFactory: @escaping KernelFactory = KernelAppViewModel.defaultKernelFactory,
        blockSourceFactory: @escaping BlockSourceFactory = KernelAppViewModel.defaultBlockSourceFactory
    ) {
        self.settings = settings
        self.kernelFactory = kernelFactory
        self.blockSourceFactory = blockSourceFactory
    }

    // MARK: - Lifecycle

    /// Open the kernel (if not already resident) and spawn the sync run.
    ///
    /// Foreground/background-agnostic per Q7 — same path is taken whether
    /// invoked from a button tap or from a `BGContinuedProcessingTask`
    /// resumption (B4).
    func start() async {
        // Q5 privacy guard — until B5 wires the SOCKS5 proxy onto the
        // block source, refuse to leak traffic the user expects to be
        // private.
        if settings.routeDownloadsThroughTor {
            snapshot = SyncSnapshot(
                phase: .failed("Tor routing requested but not yet supported in this build"),
                statusText: "Tor routing not yet supported",
                localHeight: 0,
                remoteHeight: 0,
                tipHash: Data(),
                verificationProgress: 0
            )
            return
        }

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

        // No-op if already running.
        if syncTask != nil { return }

        if residentKernel == nil {
            do {
                residentKernel = try await kernelFactory(
                    settings.chainType,
                    settings.effectiveDataDirectory,
                    settings.workerThreadCount,
                    nil
                )
            } catch {
                Self.logger.error("kernel open failed: \(String(describing: error), privacy: .public)")
                snapshot = SyncSnapshot(
                    phase: .failed(error.localizedDescription),
                    statusText: "Kernel open failed",
                    localHeight: 0,
                    remoteHeight: 0,
                    tipHash: Data(),
                    verificationProgress: 0
                )
                return
            }
        }

        spawnSyncTask(endpoint: endpoint)
        lastAppliedSnapshot = KernelAppSettingsSnapshot(settings: settings)
    }

    /// Tear down the resident kernel and rebuild it with the requested
    /// wipe flags, then resume sync.
    ///
    /// Q4 + Q1: per-mode wipe flags pass through ``ResidentKernel/make``
    /// → ``ChainstateManagerOptions/setWipeDBs(blockTreeDB:chainstateDB:)``.
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

        do {
            residentKernel = try await kernelFactory(
                settings.chainType,
                settings.effectiveDataDirectory,
                settings.workerThreadCount,
                mode
            )
        } catch {
            Self.logger.error("reindex kernel open failed: \(String(describing: error), privacy: .public)")
            snapshot = SyncSnapshot(
                phase: .failed(error.localizedDescription),
                statusText: "Reindex kernel open failed",
                localHeight: 0,
                remoteHeight: 0,
                tipHash: Data(),
                verificationProgress: 0
            )
            return
        }

        spawnSyncTask(endpoint: endpoint)
        lastAppliedSnapshot = KernelAppSettingsSnapshot(settings: settings)
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
            // source. Mirrors the privacy guard + endpoint precondition
            // in `start()`.
            if settings.routeDownloadsThroughTor {
                await cancelSyncTask()
                snapshot = SyncSnapshot(
                    phase: .failed("Tor routing requested but not yet supported in this build"),
                    statusText: "Tor routing not yet supported",
                    localHeight: 0,
                    remoteHeight: 0,
                    tipHash: Data(),
                    verificationProgress: 0
                )
                return
            }
            guard let endpoint = settings.blockSourceEndpoint else {
                await cancelSyncTask()
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
            spawnSyncTask(endpoint: endpoint)
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

    private func spawnSyncTask(endpoint: URL) {
        guard let kernel = residentKernel else { return }
        let source = blockSourceFactory(endpoint)
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
    static func defaultBlockSourceFactory(endpoint: URL) -> any BlockSource {
        EsploraBlockSource(endpoint: endpoint)
    }
}
