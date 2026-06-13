//
//  BootValidatingEngine.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

// Boot Bitcoin Core's consensus-validation engine into a fresh regtest data
// directory and confirm the chainstate has loaded by reading the tip height.

import BitcoinKernel
import Foundation

// Pick a network. Regtest is the empty, no-internet chain that boots instantly at genesis.
let context = try Context(chain: .regtest)

// Throwaway data directory inside the system temp dir.
let dataDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
    .path(percentEncoded: false)

let manager = try ChainstateManager(context: context, dataDirectory: dataDirectory)

print(manager.bestEntry.height)  // 0 on a fresh regtest directory
