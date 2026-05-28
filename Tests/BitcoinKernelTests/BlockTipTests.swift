//
//  BlockTipTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
import BitcoinKernel
import Foundation

// MARK: - BlockTip

@Test func blockTipEquality() {
    let hash = Data(repeating: 0xAB, count: 32)
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let a = BlockTip(hash: hash, height: 800_000, timestamp: timestamp)
    let b = BlockTip(hash: hash, height: 800_000, timestamp: timestamp)
    #expect(a == b)
}

@Test func blockTipInequalityByHeight() {
    let hash = Data(repeating: 0xAB, count: 32)
    let a = BlockTip(hash: hash, height: 800_000, timestamp: nil)
    let b = BlockTip(hash: hash, height: 800_001, timestamp: nil)
    #expect(a != b)
}

@Test func blockTipInequalityByHash() {
    let a = BlockTip(hash: Data(repeating: 0xAB, count: 32), height: 800_000, timestamp: nil)
    let b = BlockTip(hash: Data(repeating: 0xCD, count: 32), height: 800_000, timestamp: nil)
    #expect(a != b)
}

@Test func blockTipInequalityByTimestamp() {
    let hash = Data(repeating: 0xAB, count: 32)
    let a = BlockTip(hash: hash, height: 800_000, timestamp: Date(timeIntervalSince1970: 1_700_000_000))
    let b = BlockTip(hash: hash, height: 800_000, timestamp: Date(timeIntervalSince1970: 1_700_000_001))
    #expect(a != b)
}

@Test func blockTipHashableConsistentWithEquality() {
    let hash = Data(repeating: 0xAB, count: 32)
    let a = BlockTip(hash: hash, height: 800_000, timestamp: nil)
    let b = BlockTip(hash: hash, height: 800_000, timestamp: nil)
    var set: Set<BlockTip> = []
    set.insert(a)
    set.insert(b)
    #expect(set.count == 1)
}

@Test func blockTipOptionalTimestampDefaultsToNil() {
    let hash = Data(repeating: 0, count: 32)
    let tip = BlockTip(hash: hash, height: 0)
    #expect(tip.timestamp == nil)
}

@Test func blockTipStoresAllFields() {
    let hash = Data(repeating: 0x42, count: 32)
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let tip = BlockTip(hash: hash, height: 123_456, timestamp: timestamp)
    #expect(tip.hash == hash)
    #expect(tip.height == 123_456)
    #expect(tip.timestamp == timestamp)
}

// MARK: - Precondition (exit tests)
//
// Swift Testing 6.2+ exit tests (`#expect(processExitsWith:)`) spawn a child
// process that runs the closure body. Precondition traps terminate the child
// cleanly; the parent observes the `.failure` exit condition.
//
// Exit-test closures cannot capture parent state (per SE-0008), so each bad
// input is hard-coded as a literal inside the closure body.

@Test func blockTipPreconditionOn31ByteHash() async {
    await #expect(processExitsWith: .failure) {
        _ = BlockTip(hash: Data(repeating: 0, count: 31), height: 0)
    }
}

@Test func blockTipPreconditionOn33ByteHash() async {
    await #expect(processExitsWith: .failure) {
        _ = BlockTip(hash: Data(repeating: 0, count: 33), height: 0)
    }
}

@Test func blockTipPreconditionOnEmptyHash() async {
    await #expect(processExitsWith: .failure) {
        _ = BlockTip(hash: Data(), height: 0)
    }
}
