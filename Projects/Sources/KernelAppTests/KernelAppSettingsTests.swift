//
//  KernelAppSettingsTests.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import BitcoinKernel
import Foundation
import Testing
@testable import KernelApp

// MARK: - Test helpers

/// Returns a fresh ``UserDefaults`` instance with a unique suite name so
/// each test has an isolated backing store that doesn't leak into the
/// shared domain.
@MainActor
private func makeVolatileDefaults(function: String = #function) -> UserDefaults {
    let suiteName = "dev.21.KernelAppTests.\(UUID().uuidString).\(function)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

// MARK: - KernelAppSettingsTests

@Suite("KernelAppSettings")
@MainActor
struct KernelAppSettingsTests {

    // MARK: Defaults

    @Test("Defaults to signet when no prior state is persisted")
    func defaultsToSignet() {
        let settings = KernelAppSettings(defaults: makeVolatileDefaults())
        #expect(settings.chainType == .signet)
    }

    @Test("Block-source endpoint is nil by default so first-launch picker shows")
    func blockSourceEndpointNilByDefault() {
        let settings = KernelAppSettings(defaults: makeVolatileDefaults())
        #expect(settings.blockSourceEndpoint == nil)
        #expect(settings.needsBlockSourceSelection)
    }

    @Test("Data-directory override is nil by default")
    func dataDirectoryOverrideNilByDefault() {
        let settings = KernelAppSettings(defaults: makeVolatileDefaults())
        #expect(settings.dataDirectoryOverride == nil)
    }

    @Test("Tor off by default")
    func torOffByDefault() {
        let settings = KernelAppSettings(defaults: makeVolatileDefaults())
        #expect(!settings.torEnabled)
        #expect(!settings.routeDownloadsThroughTor)
    }

    @Test("Worker threads defaults to 0 (kernel auto-detect)")
    func workerThreadsDefaultsToZero() {
        let settings = KernelAppSettings(defaults: makeVolatileDefaults())
        #expect(settings.workerThreadCount == 0)
    }

    @Test("Logging enabled by default, internal off, with compact default category set")
    func loggingDefaults() {
        let settings = KernelAppSettings(defaults: makeVolatileDefaults())
        #expect(settings.loggingEnabled)
        #expect(!settings.loggingInternal)
        #expect(settings.enabledLogCategories == KernelAppSettings.defaultEnabledCategories)
        #expect(settings.logLevel == .info)
        #expect(settings.logFormatIncludesTimestamps)
        #expect(settings.logFormatIncludesCategoryLevels)
        #expect(!settings.logFormatIncludesTimestampMicros)
        #expect(!settings.logFormatIncludesThreadNames)
        #expect(!settings.logFormatIncludesSourceLocations)
    }

    // MARK: Persistence

    @Test("Chain-type change writes through to UserDefaults")
    func chainTypePersists() {
        let defaults = makeVolatileDefaults()
        let settings = KernelAppSettings(defaults: defaults)

        settings.chainType = .regtest

        #expect(defaults.integer(forKey: KernelAppSettings.Key.chainType) == Int(ChainType.regtest.rawValue))
    }

    @Test("Endpoint change writes URL string through to UserDefaults")
    func blockSourceEndpointPersists() {
        let defaults = makeVolatileDefaults()
        let settings = KernelAppSettings(defaults: defaults)
        let url = URL(string: "https://mempool.space/signet/api")!

        settings.blockSourceEndpoint = url

        #expect(defaults.string(forKey: KernelAppSettings.Key.blockSourceEndpoint) == url.absoluteString)
    }

    @Test("Clearing endpoint writes nil through to UserDefaults")
    func clearingEndpointRemovesValue() {
        let defaults = makeVolatileDefaults()
        let settings = KernelAppSettings(defaults: defaults)
        settings.blockSourceEndpoint = URL(string: "https://mempool.space/signet/api")!

        settings.blockSourceEndpoint = nil

        #expect(defaults.string(forKey: KernelAppSettings.Key.blockSourceEndpoint) == nil)
    }

    @Test("Round-trip: persisted settings hydrate into a second model instance")
    func persistenceRoundTrip() {
        let defaults = makeVolatileDefaults()
        do {
            let settings = KernelAppSettings(defaults: defaults)
            settings.chainType = .testnet4
            settings.blockSourceEndpoint = URL(string: "https://blockstream.info/testnet/api")
            settings.torEnabled = true
            settings.routeDownloadsThroughTor = true
            settings.workerThreadCount = 2
            settings.logLevel = .debug
            settings.enabledLogCategories = [.validation, .levelDB]
        }

        let reloaded = KernelAppSettings(defaults: defaults)
        #expect(reloaded.chainType == .testnet4)
        #expect(reloaded.blockSourceEndpoint?.absoluteString == "https://blockstream.info/testnet/api")
        #expect(reloaded.torEnabled)
        #expect(reloaded.routeDownloadsThroughTor)
        #expect(reloaded.workerThreadCount == 2)
        #expect(reloaded.logLevel == .debug)
        #expect(reloaded.enabledLogCategories == [.validation, .levelDB])
    }

    // MARK: Worker-thread clamping

    @Test("Negative worker-thread count clamps to 0")
    func workerThreadClampsNegative() {
        let settings = KernelAppSettings(defaults: makeVolatileDefaults())
        settings.workerThreadCount = -4
        #expect(settings.workerThreadCount == 0)
    }

    @Test("Worker-thread count clamps to the declared ceiling")
    func workerThreadClampsAboveCeiling() {
        let settings = KernelAppSettings(defaults: makeVolatileDefaults())
        settings.workerThreadCount = settings.maxWorkerThreads + 100
        #expect(settings.workerThreadCount == settings.maxWorkerThreads)
    }

    @Test("maxWorkerThreads reports a sensible kernel-compatible value")
    func maxWorkerThreadsReasonable() {
        let settings = KernelAppSettings(defaults: makeVolatileDefaults())
        #expect(settings.maxWorkerThreads >= 1)
        #expect(settings.maxWorkerThreads <= 15) // kernel's internal cap
    }

    // MARK: Effective data directory

    @Test("Effective data directory falls through to Application Support default")
    func effectiveDataDirectoryUsesDefault() {
        let settings = KernelAppSettings(defaults: makeVolatileDefaults())
        settings.chainType = .signet
        let expected = KernelAppSettings.defaultDataDirectory(for: .signet)
        #expect(settings.effectiveDataDirectory == expected)
    }

    @Test("Effective data directory honors override when set")
    func effectiveDataDirectoryHonorsOverride() {
        let settings = KernelAppSettings(defaults: makeVolatileDefaults())
        let custom = URL(fileURLWithPath: "/tmp/custom-kernel-data", isDirectory: true)
        settings.dataDirectoryOverride = custom
        #expect(settings.effectiveDataDirectory == custom)
    }

    @Test("Default data directory includes chain-type subdirectory")
    func defaultDataDirectoryIncludesChainName() {
        let signetDir = KernelAppSettings.defaultDataDirectory(for: .signet)
        let regtestDir = KernelAppSettings.defaultDataDirectory(for: .regtest)
        #expect(signetDir.lastPathComponent == "signet")
        #expect(regtestDir.lastPathComponent == "regtest")
        #expect(signetDir.deletingLastPathComponent().lastPathComponent == "KernelApp")
    }

    @Test("prepareDataDirectory creates the directory and marks it excluded from backup")
    func prepareDataDirectoryMarksExcludedFromBackup() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("KernelAppSettingsTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try KernelAppSettings.prepareDataDirectory(at: tempRoot)

        #expect(FileManager.default.fileExists(atPath: tempRoot.path))
        let values = try tempRoot.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }
}

// MARK: - BlockSourcePresetTests

@Suite("BlockSourcePreset")
struct BlockSourcePresetTests {

    @Test("mempool.space mainnet preset points at the canonical API root")
    func mempoolMainnetURL() {
        #expect(BlockSourcePreset.mempoolSpaceMainnet.url == URL(string: "https://mempool.space/api"))
    }

    @Test("mempool.space signet preset points at the signet API root")
    func mempoolSignetURL() {
        #expect(BlockSourcePreset.mempoolSpaceSignet.url == URL(string: "https://mempool.space/signet/api"))
    }

    @Test("blockstream.info mainnet preset points at the canonical API root")
    func blockstreamMainnetURL() {
        #expect(BlockSourcePreset.blockstreamInfoMainnet.url == URL(string: "https://blockstream.info/api"))
    }

    @Test("presets(for:) returns only presets for the requested chain")
    func presetsForChainFiltersCorrectly() {
        let signetPresets = BlockSourcePreset.presets(for: .signet)
        #expect(signetPresets.contains(.mempoolSpaceSignet))
        #expect(!signetPresets.contains(.mempoolSpaceMainnet))
        #expect(signetPresets.allSatisfy { $0.chainType == .signet })
    }

    @Test("presets(for:) is empty for regtest")
    func presetsForRegtestIsEmpty() {
        #expect(BlockSourcePreset.presets(for: .regtest).isEmpty)
    }

    @Test("All presets carry the same chain-type in both URL and metadata")
    func everyPresetURLMatchesChainType() {
        for preset in BlockSourcePreset.allCases {
            #expect(preset.url.absoluteString.contains(chainSegment(preset.chainType)))
        }
    }

    /// The substring expected in a preset URL for each chain type. Mainnet
    /// has no per-chain path segment; other chains live under `/<chain>/`.
    private func chainSegment(_ chainType: ChainType) -> String {
        switch chainType {
        case .mainnet:  return "/api"          // no per-chain segment
        case .testnet:  return "/testnet/"
        case .testnet4: return "/testnet4/"
        case .signet:   return "/signet/"
        case .regtest:  return "/regtest/"     // unused — no regtest presets
        }
    }
}
