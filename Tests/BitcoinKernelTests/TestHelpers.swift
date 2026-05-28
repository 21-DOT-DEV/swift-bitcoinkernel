//
//  TestHelpers.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Mainnet genesis block header (80 bytes, hex-encoded).
let genesisHeaderHex = "0100000000000000000000000000000000000000000000000000000000000000000000003ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4a29ab5f49ffff001d1dac2b7c"

/// Mainnet genesis coinbase transaction (hex-encoded).
let genesisCoinbaseTxHex = "01000000010000000000000000000000000000000000000000000000000000000000000000ffffffff4d04ffff001d0104455468652054696d65732030332f4a616e2f32303039204368616e63656c6c6f72206f6e206272696e6b206f66207365636f6e64206261696c6f757420666f722062616e6b73ffffffff0100f2052a0100000043410467e6e98da97bc2e3c861ce89e285eaf082e7b94389ef8e50e68b854fa474a6db7a90e27fe1287b0b25728b93fc25b67715bdf9c2ba27798e67f2c39fbe8d0aa2ac00000000"

/// Mainnet genesis block hash (display order / little-endian, hex-encoded).
let genesisBlockHashHex = "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"

/// Full mainnet genesis block (header + varint(1) + coinbase tx).
let genesisBlockHex = genesisHeaderHex + "01" + genesisCoinbaseTxHex

func dataFromHex(_ hex: String) -> Data {
    var data = Data(capacity: hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
        let nextIndex = hex.index(index, offsetBy: 2)
        if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
            data.append(byte)
        }
        index = nextIndex
    }
    return data
}
