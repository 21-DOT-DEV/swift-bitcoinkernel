//
//  DaemonDataDirectoryTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
import Foundation
@testable import NodeApp

@Suite("Daemon Data Directory")
struct DaemonDataDirectoryTests {

    @Test("prepareDataDirectory creates the directory and excludes it from backup")
    func backupExclusion() throws {
        let target = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NodeAppDataDirTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: target) }

        let prepared = try DaemonConfig.prepareDataDirectory(at: target)
        #expect(FileManager.default.fileExists(atPath: prepared.path))

        // Read the attribute back from a fresh URL so the value comes from disk.
        let check = URL(fileURLWithPath: target.path)
        let values = try check.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test("marking a folder twice is harmless and leaves it marked")
    func markingIsIdempotent() throws {
        // The flag can be silently cleared by later file operations, so every run
        // re-asserts it. Re-asserting must not fail, and must not clear it.
        let target = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NodeAppDataDirTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: target) }

        try DaemonConfig.prepareDataDirectory(at: target)
        DaemonConfig.excludeFromBackups(target)

        let values = try URL(fileURLWithPath: target.path)
            .resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test("a folder that cannot be reached is reported, not swallowed")
    func missingFolderThrows() {
        // Only the folder's absence stops a run. Asking to create one under a path
        // component that is a regular file cannot succeed.
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NodeAppDataDirFile-\(UUID().uuidString)")
        try? Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(throws: (any Error).self) {
            try DaemonConfig.prepareDataDirectory(at: file.appendingPathComponent("chain"))
        }
    }

    @Test("marking a folder that is not there is logged, never thrown")
    func markingMissingFolderDoesNotThrow() {
        // The backup mark is advisory and best-effort: a failure must never be the
        // reason a run declines, so this call reports nothing at all.
        let absent = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NodeAppNotThere-\(UUID().uuidString)", isDirectory: true)
        DaemonConfig.excludeFromBackups(absent)
    }

    @Test("dataDirectory is namespaced under Application Support")
    func location() {
        #expect(DaemonConfig.dataDirectory.lastPathComponent == "NodeApp")
        #expect(DaemonConfig.dataDirectory.path.contains("Application Support"))
    }
}
