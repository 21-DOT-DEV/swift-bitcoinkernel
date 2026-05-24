//
//  BlockTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
import BitcoinKernel
import Foundation

@Test func blockHeaderFromGenesis() throws {
    let headerData = dataFromHex(genesisHeaderHex)
    let header = try BlockHeader(headerData)
    #expect(header.version == 1)
    #expect(header.timestamp == 1231006505)
    #expect(header.bits == 0x1d00ffff)
    #expect(header.nonce == 2083236893)
}

@Test func blockHeaderHash() throws {
    let headerData = dataFromHex(genesisHeaderHex)
    let header = try BlockHeader(headerData)
    let hash = header.hash
    // Bitcoin displays hashes in reversed byte order; the C API uses internal order.
    let expectedHash = Data(dataFromHex(genesisBlockHashHex).reversed())
    #expect(hash.data == expectedHash)
}

@Test func blockHeaderPreviousHash() throws {
    let headerData = dataFromHex(genesisHeaderHex)
    let header = try BlockHeader(headerData)
    // Genesis block's previous hash is all zeros
    #expect(header.previousHash.data == Data(repeating: 0, count: 32))
}

@Test func blockHeaderInvalidDataThrows() {
    #expect(throws: KernelError.blockHeaderCreationFailed) {
        try BlockHeader(Data([0x00, 0x01]))
    }
}

@Test func blockHashRoundTrip() {
    let hashData = dataFromHex(genesisBlockHashHex)
    let hash = BlockHash(hashData)
    #expect(hash.data == hashData)
}

@Test func blockHashEquality() {
    let data = dataFromHex(genesisBlockHashHex)
    let hash1 = BlockHash(data)
    let hash2 = BlockHash(data)
    #expect(hash1.equals(hash2))
}

@Test func blockHashInequality() {
    let data1 = dataFromHex(genesisBlockHashHex)
    let data2 = Data(repeating: 0, count: 32)
    let hash1 = BlockHash(data1)
    let hash2 = BlockHash(data2)
    #expect(!hash1.equals(hash2))
}

// MARK: - Block

@Test func blockFromGenesisData() throws {
    let blockData = dataFromHex(genesisBlockHex)
    let block = try Block(blockData)
    #expect(block.transactionCount == 1)
}

@Test func blockTransactionAccess() throws {
    let blockData = dataFromHex(genesisBlockHex)
    let block = try Block(blockData)
    let tx = block.transaction(at: 0)
    // Genesis coinbase has 1 output of 50 BTC
    #expect(tx.outputCount == 1)
    #expect(tx.output(at: 0).amount == 5_000_000_000)
}

@Test func blockHeader() throws {
    let blockData = dataFromHex(genesisBlockHex)
    let block = try Block(blockData)
    let header = block.header
    #expect(header.version == 1)
    #expect(header.timestamp == 1231006505)
    #expect(header.nonce == 2083236893)
}

@Test func blockHash() throws {
    let blockData = dataFromHex(genesisBlockHex)
    let block = try Block(blockData)
    // Block.hash should match header hash
    let headerData = dataFromHex(genesisHeaderHex)
    let header = try BlockHeader(headerData)
    #expect(block.hash.equals(header.hash))
}

@Test func blockRoundTrip() throws {
    let blockData = dataFromHex(genesisBlockHex)
    let block = try Block(blockData)
    let serialized = block.data
    #expect(serialized == blockData)
}

@Test func blockInvalidDataThrows() {
    #expect(throws: KernelError.blockCreationFailed) {
        try Block(Data([0x00, 0x01, 0x02]))
    }
}
