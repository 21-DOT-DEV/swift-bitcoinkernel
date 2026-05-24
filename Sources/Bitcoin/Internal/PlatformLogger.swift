//
//  PlatformLogger.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

// On Apple platforms we use os.Logger from os.log. On Linux there is no
// equivalent; the shim below mimics just the surface this codebase uses
// (init(subsystem:category:), info, warning) and forwards to stderr so
// the same call sites compile and produce visible output.

#if canImport(os)
@_exported import os.log
#else
import Foundation

struct Logger: Sendable {
    let subsystem: String
    let category: String

    init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
    }

    func info(_ message: String) {
        FileHandle.standardError.write(Data("[\(subsystem):\(category)] info: \(message)\n".utf8))
    }

    func warning(_ message: String) {
        FileHandle.standardError.write(Data("[\(subsystem):\(category)] warning: \(message)\n".utf8))
    }
}
#endif
