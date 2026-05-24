//
//  MempoolModelTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
import Foundation
@testable import Bitcoin

/// Decode tests for Phase 2 mempool models.
/// Each test uses inline JSON matching Bitcoin Core v31.x regtest output.
@Suite("Mempool Model Decoding")
struct MempoolModelTests {

    // MARK: - MempoolInfo

    @Test("MempoolInfo decodes from Core JSON")
    func mempoolInfoDecode() throws {
        let json = """
        {
          "loaded": true,
          "size": 3,
          "bytes": 1234,
          "usage": 5678,
          "total_fee": 0.00012340,
          "maxmempool": 300000000,
          "mempoolminfee": 0.00001000,
          "minrelaytxfee": 0.00001000,
          "incrementalrelayfee": 0.00001000,
          "unbroadcastcount": 0,
          "fullrbf": false
        }
        """
        let info = try JSONDecoder().decode(MempoolInfo.self, from: Data(json.utf8))
        #expect(info.loaded)
        #expect(info.size == 3)
        #expect(info.bytes == 1234)
        #expect(info.usage == 5678)
        #expect(info.totalFee == BTCAmount(satoshis: 12340))
        #expect(info.maxmempool == 300_000_000)
        #expect(info.mempoolminfee == 0.00001)
        #expect(info.minrelaytxfee == 0.00001)
        #expect(info.incrementalrelayfee == 0.00001)
        #expect(info.unbroadcastcount == 0)
        #expect(info.fullrbf == false)
    }

    @Test("MempoolInfo decodes without optional v24+ fields")
    func mempoolInfoMinimalDecode() throws {
        let json = """
        {
          "loaded": true,
          "size": 0,
          "bytes": 0,
          "usage": 64,
          "maxmempool": 300000000,
          "mempoolminfee": 0.00001000,
          "minrelaytxfee": 0.00001000,
          "unbroadcastcount": 0
        }
        """
        let info = try JSONDecoder().decode(MempoolInfo.self, from: Data(json.utf8))
        #expect(info.loaded)
        #expect(info.size == 0)
        #expect(info.totalFee == nil)
        #expect(info.incrementalrelayfee == nil)
        #expect(info.fullrbf == nil)
    }

    // MARK: - MempoolFees

    @Test("MempoolFees decodes from Core JSON")
    func mempoolFeesDecode() throws {
        let json = """
        {
          "base": 0.00004440,
          "modified": 0.00004440,
          "ancestor": 0.00004440,
          "descendant": 0.00004440
        }
        """
        let fees = try JSONDecoder().decode(MempoolFees.self, from: Data(json.utf8))
        #expect(fees.base == BTCAmount(satoshis: 4440))
        #expect(fees.modified == BTCAmount(satoshis: 4440))
        #expect(fees.ancestor == BTCAmount(satoshis: 4440))
        #expect(fees.descendant == BTCAmount(satoshis: 4440))
    }

    // MARK: - MempoolEntry

    @Test("MempoolEntry decodes from Core JSON")
    func mempoolEntryDecode() throws {
        let json = """
        {
          "vsize": 141,
          "weight": 561,
          "time": 1713300100,
          "height": 102,
          "descendantcount": 1,
          "descendantsize": 141,
          "ancestorcount": 1,
          "ancestorsize": 141,
          "wtxid": "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234",
          "fees": {
            "base": 0.00004440,
            "modified": 0.00004440,
            "ancestor": 0.00004440,
            "descendant": 0.00004440
          },
          "depends": [],
          "spentby": ["ef012345ef012345ef012345ef012345ef012345ef012345ef012345ef012345"],
          "bip125-replaceable": true,
          "unbroadcast": false,
          "fee": 0.00004440,
          "modifiedfee": 0.00004440,
          "descendantfees": 4440,
          "ancestorfees": 4440
        }
        """
        let entry = try JSONDecoder().decode(MempoolEntry.self, from: Data(json.utf8))
        #expect(entry.vsize == 141)
        #expect(entry.weight == 561)
        #expect(entry.time.seconds == 1713300100)
        #expect(entry.height == 102)
        #expect(entry.descendantcount == 1)
        #expect(entry.descendantsize == 141)
        #expect(entry.ancestorcount == 1)
        #expect(entry.ancestorsize == 141)
        #expect(entry.wtxid == "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234")
        #expect(entry.fees.base == BTCAmount(satoshis: 4440))
        #expect(entry.fees.modified == BTCAmount(satoshis: 4440))
        #expect(entry.fees.ancestor == BTCAmount(satoshis: 4440))
        #expect(entry.fees.descendant == BTCAmount(satoshis: 4440))
        #expect(entry.depends.isEmpty)
        #expect(entry.spentby.count == 1)
        #expect(entry.bip125Replaceable)
        #expect(!entry.unbroadcast)
        // Deprecated fields
        #expect(entry.fee == BTCAmount(satoshis: 4440))
        #expect(entry.modifiedfee == BTCAmount(satoshis: 4440))
        #expect(entry.descendantfees == 4440)
        #expect(entry.ancestorfees == 4440)
    }

    @Test("MempoolEntry decodes without deprecated fields")
    func mempoolEntryWithoutDeprecatedDecode() throws {
        let json = """
        {
          "vsize": 222,
          "weight": 888,
          "time": 1713300200,
          "height": 103,
          "descendantcount": 2,
          "descendantsize": 363,
          "ancestorcount": 1,
          "ancestorsize": 222,
          "wtxid": "1111111111111111111111111111111111111111111111111111111111111111",
          "fees": {
            "base": 0.00002880,
            "modified": 0.00002880,
            "ancestor": 0.00002880,
            "descendant": 0.00005760
          },
          "depends": ["2222222222222222222222222222222222222222222222222222222222222222"],
          "spentby": [],
          "bip125-replaceable": false,
          "unbroadcast": true
        }
        """
        let entry = try JSONDecoder().decode(MempoolEntry.self, from: Data(json.utf8))
        #expect(entry.vsize == 222)
        #expect(entry.height == 103)
        #expect(entry.descendantcount == 2)
        #expect(entry.fees.descendant == BTCAmount(satoshis: 5760))
        #expect(entry.depends.count == 1)
        #expect(entry.spentby.isEmpty)
        #expect(!entry.bip125Replaceable)
        #expect(entry.unbroadcast)
        // Deprecated fields absent
        #expect(entry.fee == nil)
        #expect(entry.modifiedfee == nil)
        #expect(entry.descendantfees == nil)
        #expect(entry.ancestorfees == nil)
    }

    // MARK: - Verbose mempool (dictionary decode)

    @Test("Verbose mempool response decodes as [String: MempoolEntry]")
    func verboseMempoolDecode() throws {
        let json = """
        {
          "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233": {
            "vsize": 141,
            "weight": 561,
            "time": 1713300100,
            "height": 102,
            "descendantcount": 1,
            "descendantsize": 141,
            "ancestorcount": 1,
            "ancestorsize": 141,
            "wtxid": "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
            "fees": {
              "base": 0.00001000,
              "modified": 0.00001000,
              "ancestor": 0.00001000,
              "descendant": 0.00001000
            },
            "depends": [],
            "spentby": [],
            "bip125-replaceable": false,
            "unbroadcast": false
          }
        }
        """
        let mempool = try JSONDecoder().decode([String: MempoolEntry].self, from: Data(json.utf8))
        #expect(mempool.count == 1)
        let txid = "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233"
        let entry = try #require(mempool[txid])
        #expect(entry.vsize == 141)
        #expect(entry.fees.base == BTCAmount(satoshis: 1000))
    }
}
