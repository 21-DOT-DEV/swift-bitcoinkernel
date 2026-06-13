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

    @Test("dataDirectory is namespaced under Application Support")
    func location() {
        #expect(DaemonConfig.dataDirectory.lastPathComponent == "NodeApp")
        #expect(DaemonConfig.dataDirectory.path.contains("Application Support"))
    }
}
