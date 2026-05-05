//
//  KernelAppSettings.swift
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

// MARK: - KernelAppSettings

/// Observable, ``UserDefaults``-backed settings model for KernelApp.
///
/// All persistent user preferences flow through this single model so views
/// can bind to it and the view model can read a coherent snapshot when
/// starting the kernel. Follows the pattern of ``TorViewModel`` — a
/// `@MainActor @Observable` class with stored properties that `didSet`
/// through to ``UserDefaults``.
///
/// ### Persistence strategy
///
/// Properties are regular stored `var`s initialized in ``init(defaults:)``
/// from the backing ``UserDefaults`` and re-written via `didSet`. This keeps
/// the ``Observable`` macro's synthesized tracking intact — computed
/// properties reading ``UserDefaults`` every access would defeat observation.
///
/// ### No hardcoded block-source default
///
/// ``blockSourceEndpoint`` starts as `nil`. ``needsBlockSourceSelection``
/// drives the first-launch picker sheet in `ContentView`; the user must make
/// an explicit choice before sync can start. There is no fallback — KernelApp
/// does not decide which block explorer to trust on the user's behalf.
@MainActor @Observable
final class KernelAppSettings {

    // MARK: - Network

    /// The Bitcoin network to sync. Defaults to ``ChainType/signet`` — the
    /// recommended target per ``ChainType/signet``'s documentation (small,
    /// predictable, no mobile-size concerns).
    var chainType: ChainType {
        didSet { defaults.set(Int(chainType.rawValue), forKey: Key.chainType) }
    }

    /// User-selected HTTP block source. `nil` until the user picks one on
    /// first launch — intentionally no default. See
    /// ``needsBlockSourceSelection``.
    var blockSourceEndpoint: URL? {
        didSet { defaults.set(blockSourceEndpoint?.absoluteString, forKey: Key.blockSourceEndpoint) }
    }

    /// Overrides the computed Application-Support data directory. `nil` =
    /// use ``effectiveDataDirectory``'s default, which is
    /// `Application Support/KernelApp/<chain>/` with
    /// ``URLResourceKey/isExcludedFromBackupKey`` set to `true`.
    var dataDirectoryOverride: URL? {
        didSet { defaults.set(dataDirectoryOverride?.absoluteString, forKey: Key.dataDirectoryOverride) }
    }

    // MARK: - Privacy

    /// When `true`, the sync engine's ``URLSession`` is configured with
    /// the Tor SOCKS5 proxy, and `KernelApp` auto-manages the lifecycle
    /// of the in-process Tor client accordingly. When `false`, block
    /// fetches go direct over HTTPS and the Tor client stays stopped.
    ///
    /// `KernelApp` exposes this as the single user-facing Tor control
    /// — unlike `NodeApp`, which keeps master-switch and routing
    /// settings independent because Tor there has independent utility
    /// (onion peers, private broadcast). `KernelApp` has no such
    /// orthogonal use case.
    var routeDownloadsThroughTor: Bool {
        didSet { defaults.set(routeDownloadsThroughTor, forKey: Key.routeDownloadsThroughTor) }
    }

    // MARK: - Advanced

    /// Worker-thread count forwarded to
    /// ``ChainstateManagerOptions/setWorkerThreads(_:)``. `0` (default) means
    /// the kernel auto-detects, matching Bitcoin Core's `-par=0`. Clamped to
    /// `0...maxWorkerThreads` on write.
    var workerThreadCount: Int32 {
        didSet {
            let clamped = Self.clampWorkerThreadCount(workerThreadCount)
            if clamped != workerThreadCount {
                workerThreadCount = clamped // re-enters didSet; guarded by equality
                return
            }
            defaults.set(Int(workerThreadCount), forKey: Key.workerThreadCount)
        }
    }

    /// Upper bound for the ``workerThreadCount`` stepper. Reflects the
    /// device's available logical cores at model-init time.
    let maxWorkerThreads: Int32

    // MARK: - Logging

    /// Master switch for attaching a ``LoggingConnection``. When `false`,
    /// KernelApp does not construct a connection — swift-bitcoin's logging
    /// is opt-in by construction, so no log output is emitted at all.
    var loggingEnabled: Bool {
        didSet { defaults.set(loggingEnabled, forKey: Key.loggingEnabled) }
    }

    /// Include swift-bitcoin's own internal log lines alongside kernel
    /// output.
    var loggingInternal: Bool {
        didSet { defaults.set(loggingInternal, forKey: Key.loggingInternal) }
    }

    /// Per-category enable state — maps each ``LogCategory`` (except ``all``)
    /// to whether it routes to the active ``LoggingConnection``. Defaults to
    /// a compact signal-rich set; see ``defaultEnabledCategories``.
    var enabledLogCategories: Set<LogCategory> {
        didSet {
            let rawValues = enabledLogCategories.map { Int($0.rawValue) }.sorted()
            defaults.set(rawValues, forKey: Key.enabledLogCategories)
        }
    }

    /// Severity threshold applied uniformly across all enabled categories.
    var logLevel: LogLevel {
        didSet { defaults.set(Int(logLevel.rawValue), forKey: Key.logLevel) }
    }

    /// Prepend `[yyyy-MM-dd HH:mm:ss]` to every log line.
    var logFormatIncludesTimestamps: Bool {
        didSet { defaults.set(logFormatIncludesTimestamps, forKey: Key.logFormatTimestamps) }
    }

    /// Upgrade timestamps to microsecond precision.
    var logFormatIncludesTimestampMicros: Bool {
        didSet { defaults.set(logFormatIncludesTimestampMicros, forKey: Key.logFormatTimestampMicros) }
    }

    /// Prepend the kernel's thread name to each line.
    var logFormatIncludesThreadNames: Bool {
        didSet { defaults.set(logFormatIncludesThreadNames, forKey: Key.logFormatThreadNames) }
    }

    /// Prepend `file:line` of the C++ source call site.
    var logFormatIncludesSourceLocations: Bool {
        didSet { defaults.set(logFormatIncludesSourceLocations, forKey: Key.logFormatSourceLocations) }
    }

    /// Prepend `[category:level]` to each line.
    var logFormatIncludesCategoryLevels: Bool {
        didSet { defaults.set(logFormatIncludesCategoryLevels, forKey: Key.logFormatCategoryLevels) }
    }

    // MARK: - Init

    @ObservationIgnored private let defaults: UserDefaults

    /// Creates a settings model hydrated from ``UserDefaults``.
    ///
    /// - Parameter defaults: The backing store; pass a volatile
    ///   `UserDefaults(suiteName:)` in tests to avoid polluting the shared
    ///   domain.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Network
        let chainRaw = defaults.object(forKey: Key.chainType) as? Int ?? Int(ChainType.signet.rawValue)
        self.chainType = ChainType(rawValue: UInt8(chainRaw)) ?? .signet
        if let endpointString = defaults.string(forKey: Key.blockSourceEndpoint),
           let endpoint = URL(string: endpointString) {
            self.blockSourceEndpoint = endpoint
        } else {
            self.blockSourceEndpoint = nil
        }
        if let overrideString = defaults.string(forKey: Key.dataDirectoryOverride),
           let overrideURL = URL(string: overrideString) {
            self.dataDirectoryOverride = overrideURL
        } else {
            self.dataDirectoryOverride = nil
        }

        // Privacy
        self.routeDownloadsThroughTor = defaults.bool(forKey: Key.routeDownloadsThroughTor)

        // Advanced
        self.maxWorkerThreads = Self.computeMaxWorkerThreads()
        let rawThreads = defaults.object(forKey: Key.workerThreadCount) as? Int ?? 0
        self.workerThreadCount = Self.clampWorkerThreadCount(Int32(rawThreads), upperBound: self.maxWorkerThreads)

        // Logging
        self.loggingEnabled = (defaults.object(forKey: Key.loggingEnabled) as? Bool) ?? true
        self.loggingInternal = defaults.bool(forKey: Key.loggingInternal)
        if let rawArray = defaults.array(forKey: Key.enabledLogCategories) as? [Int] {
            self.enabledLogCategories = Set(rawArray.compactMap { LogCategory(rawValue: UInt8($0)) })
        } else {
            self.enabledLogCategories = Self.defaultEnabledCategories
        }
        let rawLevel = defaults.object(forKey: Key.logLevel) as? Int ?? Int(LogLevel.info.rawValue)
        self.logLevel = LogLevel(rawValue: UInt8(rawLevel)) ?? .info
        self.logFormatIncludesTimestamps = (defaults.object(forKey: Key.logFormatTimestamps) as? Bool) ?? true
        self.logFormatIncludesTimestampMicros = defaults.bool(forKey: Key.logFormatTimestampMicros)
        self.logFormatIncludesThreadNames = defaults.bool(forKey: Key.logFormatThreadNames)
        self.logFormatIncludesSourceLocations = defaults.bool(forKey: Key.logFormatSourceLocations)
        self.logFormatIncludesCategoryLevels = (defaults.object(forKey: Key.logFormatCategoryLevels) as? Bool) ?? true
    }

    // MARK: - Derived state

    /// `true` when no block source has been selected yet. Drives the
    /// first-launch picker sheet.
    var needsBlockSourceSelection: Bool { blockSourceEndpoint == nil }

    /// Resolves the effective data directory for the current chain:
    /// ``dataDirectoryOverride`` if set, otherwise
    /// `Application Support/KernelApp/<chain>/`.
    ///
    /// Does **not** create the directory or apply
    /// ``URLResourceKey/isExcludedFromBackupKey``; ``prepareDataDirectory(at:)``
    /// handles filesystem side effects so pure reads stay non-mutating.
    var effectiveDataDirectory: URL {
        if let override = dataDirectoryOverride { return override }
        return Self.defaultDataDirectory(for: chainType)
    }

    // MARK: - Filesystem helpers

    /// Computes the default Application-Support-rooted data directory for a
    /// given chain, without creating it on disk.
    ///
    /// - Parameter chainType: Chain whose directory to compute.
    /// - Returns: `Application Support/KernelApp/<chain>/`.
    static func defaultDataDirectory(for chainType: ChainType) -> URL {
        let appSupport: URL
        do {
            appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
        } catch {
            // Fallback — should be unreachable on Apple platforms where
            // Application Support is always resolvable for an app container.
            appSupport = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        }
        return appSupport
            .appendingPathComponent("KernelApp", isDirectory: true)
            .appendingPathComponent(chainType.description, isDirectory: true)
    }

    /// Creates the data directory if missing and marks it excluded from
    /// iCloud / iTunes backup per Apple's ["File System Basics"](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html)
    /// guidance — re-downloadable data must not be backed up.
    ///
    /// - Parameter directory: Directory to create + mark.
    /// - Throws: Filesystem errors from ``FileManager/createDirectory(at:withIntermediateDirectories:attributes:)``.
    nonisolated static func prepareDataDirectory(at directory: URL) throws {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        if !fileManager.fileExists(atPath: directory.path, isDirectory: &isDir) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = directory
        try mutableURL.setResourceValues(resourceValues)
    }

    // MARK: - Private helpers

    /// Upper bound for ``workerThreadCount``. The kernel clamps higher
    /// values internally to 15; we expose the device's active core count
    /// bounded by that kernel cap so the stepper UI makes sense.
    private static func computeMaxWorkerThreads() -> Int32 {
        let active = Int32(ProcessInfo.processInfo.activeProcessorCount)
        return min(max(active, 1), 15)
    }

    /// Clamps to `0...maxWorkerThreads`. `0` is always valid and means
    /// "auto-detect" at the kernel boundary.
    private static func clampWorkerThreadCount(
        _ value: Int32,
        upperBound: Int32? = nil
    ) -> Int32 {
        let ceiling = upperBound ?? computeMaxWorkerThreads()
        return max(0, min(value, ceiling))
    }

    // MARK: - Defaults

    /// Compact signal-rich starter set: ``LogCategory/validation`` for the
    /// block-rejection visibility that matters most, ``LogCategory/kernel``
    /// for lifecycle, ``LogCategory/reindex`` so wipe operations emit their
    /// expected progress lines.
    static let defaultEnabledCategories: Set<LogCategory> = [
        .validation,
        .kernel,
        .reindex,
    ]

    // MARK: - UserDefaults Keys

    /// Centralized key constants. `kernel_` prefix avoids collision with
    /// NodeApp's settings in a shared suite.
    enum Key {
        static let chainType = "kernel_chain_type"
        static let blockSourceEndpoint = "kernel_block_source_endpoint"
        static let dataDirectoryOverride = "kernel_data_directory_override"
        static let routeDownloadsThroughTor = "kernel_route_downloads_through_tor"
        static let workerThreadCount = "kernel_worker_thread_count"
        static let loggingEnabled = "kernel_logging_enabled"
        static let loggingInternal = "kernel_logging_internal"
        static let enabledLogCategories = "kernel_enabled_log_categories"
        static let logLevel = "kernel_log_level"
        static let logFormatTimestamps = "kernel_log_format_timestamps"
        static let logFormatTimestampMicros = "kernel_log_format_timestamp_micros"
        static let logFormatThreadNames = "kernel_log_format_thread_names"
        static let logFormatSourceLocations = "kernel_log_format_source_locations"
        static let logFormatCategoryLevels = "kernel_log_format_category_levels"
    }
}
