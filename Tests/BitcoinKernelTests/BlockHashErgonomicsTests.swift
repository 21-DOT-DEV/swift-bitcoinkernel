//
//  BlockHashErgonomicsTests.swift
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

// MARK: - BlockHash Swift-value ergonomics
//
// These tests exercise the conformances retrofitted onto `BlockHash` in
// Phase A1 Cycle 3:
//   - Equatable (operator `==`)
//   - Hashable (Set / Dictionary usability)
//   - RawRepresentable (rawValue: Data, failable init)
//   - CustomStringConvertible (display-order hex)
//
// The existing `equals(_:)` method on BlockHash is preserved — these
// additions are pure API growth.

// MARK: - Equatable

@Test func blockHashEquatableViaOperator() {
    let bytes = dataFromHex(genesisBlockHashHex)
    let a = BlockHash(bytes)
    let b = BlockHash(bytes)
    #expect(a == b)
}

@Test func blockHashEquatableDifferentBytes() {
    let a = BlockHash(dataFromHex(genesisBlockHashHex))
    let b = BlockHash(Data(repeating: 0, count: 32))
    #expect(a != b)
}

// MARK: - Hashable

@Test func blockHashHashableDeduplicatesInSet() {
    let bytes = dataFromHex(genesisBlockHashHex)
    let a = BlockHash(bytes)
    let b = BlockHash(bytes)
    var set: Set<BlockHash> = []
    set.insert(a)
    set.insert(b)
    #expect(set.count == 1)
}

@Test func blockHashHashableDistinctValuesDistinctBuckets() {
    let a = BlockHash(dataFromHex(genesisBlockHashHex))
    let b = BlockHash(Data(repeating: 0xAB, count: 32))
    let set: Set<BlockHash> = [a, b]
    #expect(set.count == 2)
}

// MARK: - RawRepresentable

@Test func blockHashRawRepresentableExposesData() {
    let bytes = Data(repeating: 0x42, count: 32)
    let hash = BlockHash(bytes)
    // rawValue must equal the internal-order `data` accessor.
    #expect(hash.rawValue == hash.data)
    #expect(hash.rawValue == bytes)
}

@Test func blockHashRawRepresentableFailableInitSucceedsOnCorrectSize() {
    let bytes = Data(repeating: 0xCD, count: 32)
    let hash = BlockHash(rawValue: bytes)
    #expect(hash != nil)
    #expect(hash?.rawValue == bytes)
}

@Test func blockHashRawRepresentableFailableInitReturnsNilOnWrongSize() {
    // 31, 33, 0 bytes should all fail gracefully — no precondition crash.
    #expect(BlockHash(rawValue: Data(repeating: 0, count: 31)) == nil)
    #expect(BlockHash(rawValue: Data(repeating: 0, count: 33)) == nil)
    #expect(BlockHash(rawValue: Data()) == nil)
}

// MARK: - CustomStringConvertible

@Test func blockHashDescriptionIsDisplayOrderHex() {
    // Genesis block hash is canonically written in display order
    // (reversed from the internal byte order stored by the C API).
    let internalBytes = Data(dataFromHex(genesisBlockHashHex).reversed())
    let hash = BlockHash(internalBytes)
    #expect(String(describing: hash) == genesisBlockHashHex)
    #expect(hash.description == genesisBlockHashHex)
}

@Test func blockHashDescriptionIsLowercase64HexChars() {
    let hash = BlockHash(Data(repeating: 0, count: 32))
    let desc = hash.description
    #expect(desc.count == 64)
    #expect(desc == String(repeating: "0", count: 64))
    // All characters must be hex digits.
    #expect(desc.allSatisfy { $0.isHexDigit })
}
