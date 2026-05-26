//
//  RegtestChainBuilder.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

// RegtestChainBuilder uses CryptoKit's SHA256 for synthetic block mining.
// CryptoKit is Apple-only; on Linux the same API is provided by
// swift-crypto, but adding that dependency requires a constitutional
// amendment per `AGENTS.md`. Until that lands, this support file (and
// the integration tests that depend on it) compile on Apple platforms
// only. See `roadmap.md` "Linux Test Coverage".
#if canImport(CryptoKit)

import Foundation
import CryptoKit
import BitcoinKernel

/// Mines synthetic regtest blocks on the fly for use in ``BlockchainSync``
/// integration tests that need real block data flowing through the kernel's
/// `processBlock` validation path.
///
/// Regtest's `powLimit` is ~2^255 (nBits = `0x207fffff`), so any hash whose
/// big-endian MSB is `<= 0x7F` satisfies proof-of-work — roughly half of all
/// nonces work. Mining 5 blocks costs well under a millisecond in practice.
///
/// ### Scope
///
/// - Coinbase-only blocks (no mempool transactions, no witnesses).
/// - Heights 1–16: uses `OP_N + OP_0` scriptSig (meets the 2-byte minimum).
/// - Heights 17–499: still pre-BIP34, but encodes height via `CScriptNum`.
/// - Heights 500+: not tested; BIP34 enforcement kicks in.
///
/// Output is consumable by ``BitcoinKernel/Block/init(_:)``.
enum RegtestChainBuilder {
    /// A mined block plus parsed kernel types for direct use in tests.
    struct MinedBlock {
        let height: Int
        /// 32 bytes in internal (kernel) byte order.
        let hash: Data
        /// 80-byte serialized header.
        let headerBytes: Data
        /// Full consensus-serialized block.
        let blockBytes: Data
    }

    // MARK: - Constants (regtest)

    /// Regtest `powLimit` in compact/nBits form.
    private static let regtestBits: UInt32 = 0x207f_ffff

    /// Regtest subsidy-halving interval. Matches Bitcoin Core's
    /// `consensus.nSubsidyHalvingInterval = 150` for regtest.
    private static let halvingInterval: Int = 150

    /// Initial block subsidy in satoshis (50 BTC).
    private static let initialSubsidy: UInt64 = 50 * 100_000_000

    // MARK: - Public API

    /// Subsidy for a given height on regtest.
    static func subsidy(atHeight height: Int) -> UInt64 {
        let halvings = height / halvingInterval
        if halvings >= 64 { return 0 }
        return initialSubsidy >> halvings
    }

    /// Mine a chain of `count` blocks starting at `height`, extending
    /// `previousHash`.
    ///
    /// - Parameters:
    ///   - count: Number of blocks to mine.
    ///   - startingAt: Height of the first mined block (previous block
    ///     is at `startingAt - 1`).
    ///   - previousHash: 32-byte internal-order hash of the block at
    ///     `startingAt - 1`.
    ///   - startTime: Timestamp of the first mined block (later blocks get
    ///     `startTime + i`). Must be ≥ MTP of the chain at `previousHash`;
    ///     for regtest genesis, current time is safe.
    static func mineChain(
        count: Int,
        startingAt height: Int = 1,
        previousHash: Data,
        startTime: UInt32 = UInt32(Date().timeIntervalSince1970)
    ) -> [MinedBlock] {
        var result: [MinedBlock] = []
        result.reserveCapacity(count)
        var prev = previousHash
        var time = startTime
        for i in 0..<count {
            let mined = mineOne(height: height + i, previousHash: prev, time: time)
            result.append(mined)
            prev = mined.hash
            time &+= 1
        }
        return result
    }

    // MARK: - Mining

    private static func mineOne(height: Int, previousHash: Data, time: UInt32) -> MinedBlock {
        precondition(previousHash.count == 32, "previousHash must be 32 bytes (got \(previousHash.count))")

        let coinbase = buildCoinbase(height: height)
        // Single-transaction block → merkle root == coinbase txid.
        let merkleRoot = sha256d(coinbase)

        let target = decodeCompactTarget(regtestBits)
        var nonce: UInt32 = 0
        while true {
            // Version 4 satisfies BIP34/66/65 (all active from height 1 on
            // regtest). Anything < 4 is rejected with bad-version.
            let header = buildHeader(
                version: 4,
                previousHash: previousHash,
                merkleRoot: merkleRoot,
                time: time,
                bits: regtestBits,
                nonce: nonce
            )
            let hash = sha256d(header)
            if hashIsAtOrBelowTarget(hash: hash, target: target) {
                var blockBytes = Data()
                blockBytes.reserveCapacity(header.count + 1 + coinbase.count)
                blockBytes.append(header)
                blockBytes.append(contentsOf: encodeVarInt(1))
                blockBytes.append(coinbase)
                return MinedBlock(
                    height: height,
                    hash: hash,
                    headerBytes: header,
                    blockBytes: blockBytes
                )
            }
            nonce &+= 1
            // Regtest target is ~2^255, so success is expected within a handful of
            // nonces. A full UInt32 sweep means our encoding is wrong.
            if nonce == .max {
                fatalError("RegtestChainBuilder: failed to find valid nonce for height \(height)")
            }
        }
    }

    // MARK: - Block component builders

    private static func buildHeader(
        version: Int32,
        previousHash: Data,
        merkleRoot: Data,
        time: UInt32,
        bits: UInt32,
        nonce: UInt32
    ) -> Data {
        var data = Data()
        data.reserveCapacity(80)
        data.append(contentsOf: encodeInt32LE(version))
        data.append(previousHash)
        data.append(merkleRoot)
        data.append(contentsOf: encodeUInt32LE(time))
        data.append(contentsOf: encodeUInt32LE(bits))
        data.append(contentsOf: encodeUInt32LE(nonce))
        return data
    }

    private static func buildCoinbase(height: Int) -> Data {
        var tx = Data()
        tx.reserveCapacity(128)
        // Version
        tx.append(contentsOf: encodeUInt32LE(1))
        // Input count (1)
        tx.append(contentsOf: encodeVarInt(1))
        // Input:
        //   - prevout: 32 bytes of zeros + index 0xFFFFFFFF
        tx.append(Data(repeating: 0, count: 32))
        tx.append(contentsOf: encodeUInt32LE(0xFFFF_FFFF))
        //   - scriptSig: height push + extra nonce (≥2 bytes minimum)
        let scriptSig = buildCoinbaseScriptSig(height: height)
        tx.append(contentsOf: encodeVarInt(UInt64(scriptSig.count)))
        tx.append(scriptSig)
        //   - sequence
        tx.append(contentsOf: encodeUInt32LE(0xFFFF_FFFF))
        // Output count (1)
        tx.append(contentsOf: encodeVarInt(1))
        // Output:
        //   - amount = block subsidy
        tx.append(contentsOf: encodeUInt64LE(subsidy(atHeight: height)))
        //   - scriptPubKey = OP_TRUE (anyone-can-spend; fine for regtest)
        tx.append(contentsOf: encodeVarInt(1))
        tx.append(0x51)
        // Lock time = height - 1 (matches Bitcoin Core's miner.cpp convention)
        let lockTime: UInt32 = height > 0 ? UInt32(height - 1) : 0
        tx.append(contentsOf: encodeUInt32LE(lockTime))
        return tx
    }

    private static func buildCoinbaseScriptSig(height: Int) -> Data {
        // For heights 1–16: OP_N + OP_0 (meets 2-byte minimum).
        // For higher heights: push height as CScriptNum + OP_0.
        var script = Data()
        if (1...16).contains(height) {
            script.append(0x50 + UInt8(height)) // OP_1..OP_16
            script.append(0x00)                  // OP_0 extra nonce
        } else {
            let num = encodeScriptNum(Int64(height))
            script.append(UInt8(num.count))
            script.append(num)
            script.append(0x00)
        }
        return script
    }

    // MARK: - Integer encoding (little-endian)

    private static func encodeUInt16LE(_ value: UInt16) -> [UInt8] {
        var v = value.littleEndian
        return withUnsafeBytes(of: &v) { Array($0) }
    }

    private static func encodeUInt32LE(_ value: UInt32) -> [UInt8] {
        var v = value.littleEndian
        return withUnsafeBytes(of: &v) { Array($0) }
    }

    private static func encodeInt32LE(_ value: Int32) -> [UInt8] {
        var v = value.littleEndian
        return withUnsafeBytes(of: &v) { Array($0) }
    }

    private static func encodeUInt64LE(_ value: UInt64) -> [UInt8] {
        var v = value.littleEndian
        return withUnsafeBytes(of: &v) { Array($0) }
    }

    /// Bitcoin's compact varint encoding.
    private static func encodeVarInt(_ value: UInt64) -> [UInt8] {
        if value < 0xFD {
            return [UInt8(value)]
        } else if value <= UInt64(UInt16.max) {
            return [0xFD] + encodeUInt16LE(UInt16(value))
        } else if value <= UInt64(UInt32.max) {
            return [0xFE] + encodeUInt32LE(UInt32(value))
        } else {
            return [0xFF] + encodeUInt64LE(value)
        }
    }

    /// Bitcoin's `CScriptNum` encoding. Minimal representation, with an
    /// added sign byte when the high bit of the top byte is set.
    private static func encodeScriptNum(_ value: Int64) -> Data {
        if value == 0 { return Data() }
        var abs = UInt64(value.magnitude)
        let negative = value < 0
        var result = Data()
        while abs > 0 {
            result.append(UInt8(abs & 0xFF))
            abs >>= 8
        }
        if (result.last! & 0x80) != 0 {
            result.append(negative ? 0x80 : 0x00)
        } else if negative {
            result[result.count - 1] |= 0x80
        }
        return result
    }

    // MARK: - Hashing + target

    /// Bitcoin's double-SHA256 (`sha256d`). Returns 32 bytes.
    private static func sha256d(_ data: Data) -> Data {
        let first = SHA256.hash(data: data)
        let second = SHA256.hash(data: Data(first))
        return Data(second)
    }

    /// Decode `nBits` compact representation into a 32-byte big-endian target.
    ///
    /// Formula: `target = mantissa << (8 × (exponent − 3))`, clamped to 256 bits.
    private static func decodeCompactTarget(_ bits: UInt32) -> [UInt8] {
        let exponent = Int((bits >> 24) & 0xFF)
        let mantissa = bits & 0x007F_FFFF
        var target = [UInt8](repeating: 0, count: 32)
        if exponent <= 3 {
            let shift = 8 * (3 - exponent)
            let shifted = mantissa >> shift
            target[31] = UInt8(shifted & 0xFF)
            target[30] = UInt8((shifted >> 8) & 0xFF)
            target[29] = UInt8((shifted >> 16) & 0xFF)
        } else {
            let pos = 32 - exponent
            if pos >= 0 && pos + 2 < 32 {
                target[pos] = UInt8((mantissa >> 16) & 0xFF)
                target[pos + 1] = UInt8((mantissa >> 8) & 0xFF)
                target[pos + 2] = UInt8(mantissa & 0xFF)
            }
        }
        return target
    }

    /// `hash` is in internal (little-endian) byte order; `target` is in
    /// big-endian byte order. Returns true iff `hash ≤ target` as big
    /// numbers.
    private static func hashIsAtOrBelowTarget(hash: Data, target: [UInt8]) -> Bool {
        // Reverse hash to big-endian for lexicographic comparison.
        let hashBE = Array(hash.reversed())
        for i in 0..<32 {
            if hashBE[i] < target[i] { return true }
            if hashBE[i] > target[i] { return false }
        }
        return true // exactly equal
    }
}

#endif // canImport(CryptoKit)
