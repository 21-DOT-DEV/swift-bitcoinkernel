//
//  KernelAppSettings+Logging.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2022-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import BitcoinKernel
import Foundation

// MARK: - User-facing LogCategory

/// UI-presentation metadata for a ``LogCategory``. The cases wrap the kernel
/// enum so SwiftUI can display friendly labels and subtitles without leaking
/// kernel internals into view code.
///
/// Excludes ``LogCategory/all`` from the user-facing list — toggling every
/// category at once is a footgun in the UI; use the "Enable All" button
/// instead (implemented in the logging settings view).
enum KernelLogCategoryDisplay: CaseIterable, Identifiable, Hashable {
    case bench
    case blockStorage
    case coinDB
    case levelDB
    case mempool
    case prune
    case rand
    case reindex
    case validation
    case kernel

    /// The underlying ``LogCategory`` value passed to
    /// ``enableLogCategory(_:)`` / ``disableLogCategory(_:)``.
    var category: LogCategory {
        switch self {
        case .bench:        return .bench
        case .blockStorage: return .blockStorage
        case .coinDB:       return .coinDB
        case .levelDB:      return .levelDB
        case .mempool:      return .mempool
        case .prune:        return .prune
        case .rand:         return .rand
        case .reindex:      return .reindex
        case .validation:   return .validation
        case .kernel:       return .kernel
        }
    }

    var id: LogCategory { category }

    /// Short label for the toggle row.
    var displayName: String {
        switch self {
        case .bench:        return "Benchmarks"
        case .blockStorage: return "Block Storage"
        case .coinDB:       return "UTXO Database"
        case .levelDB:      return "LevelDB"
        case .mempool:      return "Mempool"
        case .prune:        return "Prune"
        case .rand:         return "Random"
        case .reindex:      return "Reindex"
        case .validation:   return "Validation"
        case .kernel:       return "Kernel"
        }
    }

    /// Explanatory subtitle — states the signal-to-noise trade-off for each
    /// category so users can choose meaningfully.
    var subtitle: String {
        switch self {
        case .bench:
            return "Timing measurements for validation and cache operations."
        case .blockStorage:
            return "blk*.dat and rev*.dat reads, writes, and file rotation."
        case .coinDB:
            return "UTXO set cache fills, flushes, and warmup progress."
        case .levelDB:
            return "Storage backend operations. High-volume; enable for deep debugging."
        case .mempool:
            return "Transaction mempool activity. Quiet — BitcoinKernel has no mempool."
        case .prune:
            return "Block pruning. Quiet — pruning is not currently exposed."
        case .rand:
            return "Random number generator entropy sources and state."
        case .reindex:
            return "Expected progress output during chainstate wipe and rebuild."
        case .validation:
            return "Block and transaction validation — highest-signal category."
        case .kernel:
            return "Lifecycle: init, shutdown, and general kernel activity."
        }
    }
}

// MARK: - Log format flag descriptors

/// UI-presentation metadata for a log-format flag, paired with a key path
/// into ``KernelAppSettings`` so the toggle row can read and write the
/// backing property.
///
/// Grouping every format-flag toggle under one `ForEach` in the settings
/// view keeps the logging form compact and avoids a copy-paste row per
/// flag. The `ReferenceWritableKeyPath` is honored thanks to the
/// `@Observable @MainActor` class shape of ``KernelAppSettings``.
struct KernelLogFormatFlag: Identifiable, Hashable {
    let id: String
    let displayName: String
    let subtitle: String
    let keyPath: ReferenceWritableKeyPath<KernelAppSettings, Bool>

    static let all: [KernelLogFormatFlag] = [
        KernelLogFormatFlag(
            id: "timestamps",
            displayName: "Timestamps",
            subtitle: "Prepend wall-clock time to each line.",
            keyPath: \KernelAppSettings.logFormatIncludesTimestamps
        ),
        KernelLogFormatFlag(
            id: "timestamp_micros",
            displayName: "Microsecond Precision",
            subtitle: "Upgrade timestamps to microsecond precision.",
            keyPath: \KernelAppSettings.logFormatIncludesTimestampMicros
        ),
        KernelLogFormatFlag(
            id: "thread_names",
            displayName: "Thread Names",
            subtitle: "Prepend kernel thread name to each line.",
            keyPath: \KernelAppSettings.logFormatIncludesThreadNames
        ),
        KernelLogFormatFlag(
            id: "source_locations",
            displayName: "Source Locations",
            subtitle: "Prepend C++ source file:line to each line.",
            keyPath: \KernelAppSettings.logFormatIncludesSourceLocations
        ),
        KernelLogFormatFlag(
            id: "category_levels",
            displayName: "Category + Level",
            subtitle: "Prepend [category:level] tag to each line.",
            keyPath: \KernelAppSettings.logFormatIncludesCategoryLevels
        ),
    ]

    // Hashable / Equatable — exclude the key path (key paths don't have
    // useful Hashable semantics across instances); identity is the `id`.
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: KernelLogFormatFlag, rhs: KernelLogFormatFlag) -> Bool {
        lhs.id == rhs.id
    }
}
