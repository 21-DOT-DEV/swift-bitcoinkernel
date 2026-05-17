//
//  ControlMiningModelTests.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
import Foundation
@testable import Bitcoin

/// Decode tests for Phase 3 Control, Mining, and Generating models.
/// Each test uses inline JSON matching Bitcoin Core v31.x regtest output.
@Suite("Control + Mining Model Decoding")
struct ControlMiningModelTests {

    // MARK: - MemoryInfo

    @Test("MemoryInfo decodes from Core JSON (mode stats)")
    func memoryInfoDecode() throws {
        let json = """
        {
          "locked": {
            "used": 128,
            "free": 262016,
            "total": 262144,
            "locked": 262144,
            "chunks_used": 2,
            "chunks_free": 1
          }
        }
        """
        let info = try JSONDecoder().decode(MemoryInfo.self, from: Data(json.utf8))
        #expect(info.locked.used == 128)
        #expect(info.locked.free == 262016)
        #expect(info.locked.total == 262144)
        #expect(info.locked.locked == 262144)
        #expect(info.locked.chunksUsed == 2)
        #expect(info.locked.chunksFree == 1)
    }

    @Test("MemoryInfo: locked < total indicates locking failure")
    func memoryInfoPartialLock() throws {
        let json = """
        {
          "locked": {
            "used": 64,
            "free": 65472,
            "total": 65536,
            "locked": 32768,
            "chunks_used": 1,
            "chunks_free": 0
          }
        }
        """
        let info = try JSONDecoder().decode(MemoryInfo.self, from: Data(json.utf8))
        #expect(info.locked.locked < info.locked.total)
    }

    // MARK: - RPCInfo

    @Test("RPCInfo decodes from Core JSON")
    func rpcInfoDecode() throws {
        let json = """
        {
          "active_commands": [
            {
              "method": "getrpcinfo",
              "duration": 123
            }
          ],
          "logpath": "/tmp/regtest/debug.log"
        }
        """
        let info = try JSONDecoder().decode(RPCInfo.self, from: Data(json.utf8))
        #expect(info.activeCommands.count == 1)
        #expect(info.activeCommands[0].method == "getrpcinfo")
        #expect(info.activeCommands[0].duration == 123)
        #expect(info.logpath == "/tmp/regtest/debug.log")
    }

    @Test("RPCInfo decodes with empty active commands")
    func rpcInfoEmptyDecode() throws {
        let json = """
        {
          "active_commands": [],
          "logpath": "/var/log/bitcoind/debug.log"
        }
        """
        let info = try JSONDecoder().decode(RPCInfo.self, from: Data(json.utf8))
        #expect(info.activeCommands.isEmpty)
    }

    // MARK: - GeneratedBlock

    @Test("GeneratedBlock decodes from Core JSON")
    func generatedBlockDecode() throws {
        let json = """
        {"hash": "00000000839a8e6886ab5951d76f411475428afc90947ee320161bbf18eb6048"}
        """
        let block = try JSONDecoder().decode(GeneratedBlock.self, from: Data(json.utf8))
        #expect(block.hash == "00000000839a8e6886ab5951d76f411475428afc90947ee320161bbf18eb6048")
    }

    // MARK: - MiningInfo

    @Test("MiningInfo decodes from Core JSON")
    func miningInfoDecode() throws {
        let json = """
        {
          "blocks": 102,
          "currentblockweight": 4000,
          "currentblocktx": 1,
          "difficulty": 4.656542373906925e-10,
          "networkhashps": 0.003333333333333333,
          "pooledtx": 0,
          "chain": "regtest",
          "warnings": []
        }
        """
        let info = try JSONDecoder().decode(MiningInfo.self, from: Data(json.utf8))
        #expect(info.blocks == 102)
        #expect(info.currentblockweight == 4000)
        #expect(info.currentblocktx == 1)
        #expect(info.difficulty > 0)
        #expect(info.networkhashps > 0)
        #expect(info.pooledtx == 0)
        #expect(info.chain == "regtest")
        #expect(info.warnings.isEmpty)
    }

    @Test("MiningInfo decodes without optional assembled-block fields")
    func miningInfoMinimalDecode() throws {
        let json = """
        {
          "blocks": 0,
          "difficulty": 4.656542373906925e-10,
          "networkhashps": 0,
          "pooledtx": 0,
          "chain": "regtest",
          "warnings": []
        }
        """
        let info = try JSONDecoder().decode(MiningInfo.self, from: Data(json.utf8))
        #expect(info.blocks == 0)
        #expect(info.currentblockweight == nil)
        #expect(info.currentblocktx == nil)
    }

    // MARK: - BlockTemplate

    @Test("BlockTemplate decodes from Core JSON")
    func blockTemplateDecode() throws {
        let json = """
        {
          "version": 536870912,
          "rules": ["csv", "!segwit"],
          "vbavailable": {},
          "vbrequired": 0,
          "previousblockhash": "00000000839a8e6886ab5951d76f411475428afc90947ee320161bbf18eb6048",
          "transactions": [
            {
              "data": "0200000001abcdef",
              "txid": "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
              "hash": "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
              "depends": [],
              "fee": 4440,
              "sigops": 1,
              "weight": 561
            }
          ],
          "coinbaseaux": {},
          "coinbasevalue": 5000004440,
          "longpollid": "00000000839a8e6886ab5951d76f411475428afc90947ee320161bbf18eb604899",
          "target": "7fffff0000000000000000000000000000000000000000000000000000000000",
          "mintime": 1713300000,
          "mutable": ["time", "transactions", "prevblock"],
          "noncerange": "00000000ffffffff",
          "sigoplimit": 80000,
          "sizelimit": 4000000,
          "weightlimit": 4000000,
          "curtime": 1713300100,
          "bits": "207fffff",
          "height": 103,
          "default_witness_commitment": "6a24aa21a9ede2f61c3f71d1defd3fa999dfa36953755c690689799962b48bebd836974e8cf9"
        }
        """
        let tmpl = try JSONDecoder().decode(BlockTemplate.self, from: Data(json.utf8))
        #expect(tmpl.version == 536870912)
        #expect(tmpl.rules == ["csv", "!segwit"])
        #expect(tmpl.vbavailable.isEmpty)
        #expect(tmpl.vbrequired == 0)
        #expect(tmpl.previousblockhash.hasPrefix("0000"))
        #expect(tmpl.transactions.count == 1)
        #expect(tmpl.transactions[0].fee == 4440)
        #expect(tmpl.transactions[0].sigops == 1)
        #expect(tmpl.transactions[0].weight == 561)
        #expect(tmpl.transactions[0].depends.isEmpty)
        #expect(tmpl.coinbasevalue == 5_000_004_440)
        #expect(tmpl.mintime.seconds == 1713300000)
        #expect(tmpl.curtime.seconds == 1713300100)
        #expect(tmpl.mutable.contains("time"))
        #expect(tmpl.noncerange == "00000000ffffffff")
        #expect(tmpl.sigoplimit == 80000)
        #expect(tmpl.sizelimit == 4_000_000)
        #expect(tmpl.weightlimit == 4_000_000)
        #expect(tmpl.bits == "207fffff")
        #expect(tmpl.height == 103)
        #expect(tmpl.defaultWitnessCommitment != nil)
    }

    @Test("BlockTemplate decodes without optional witness commitment")
    func blockTemplateNoWitnessDecode() throws {
        let json = """
        {
          "version": 536870912,
          "rules": [],
          "vbavailable": {},
          "vbrequired": 0,
          "previousblockhash": "0f9188f13cb7b2c71f2a335e3a4fc328bf5beb436012afca590b1a11466e2206",
          "transactions": [],
          "coinbaseaux": {},
          "coinbasevalue": 5000000000,
          "longpollid": "0f9188f13cb7b2c71f2a335e3a4fc328bf5beb436012afca590b1a11466e220601",
          "target": "7fffff0000000000000000000000000000000000000000000000000000000000",
          "mintime": 1296688602,
          "mutable": ["time", "transactions", "prevblock"],
          "noncerange": "00000000ffffffff",
          "sigoplimit": 80000,
          "sizelimit": 4000000,
          "weightlimit": 4000000,
          "curtime": 1713300000,
          "bits": "207fffff",
          "height": 1
        }
        """
        let tmpl = try JSONDecoder().decode(BlockTemplate.self, from: Data(json.utf8))
        #expect(tmpl.transactions.isEmpty)
        #expect(tmpl.coinbasevalue == 5_000_000_000)
        #expect(tmpl.height == 1)
        #expect(tmpl.defaultWitnessCommitment == nil)
    }

    @Test("BlockTemplateTransaction decodes with optional fee/sigops absent")
    func blockTemplateTransactionOptionalsDecode() throws {
        let json = """
        {
          "data": "020000000100",
          "txid": "1111111111111111111111111111111111111111111111111111111111111111",
          "hash": "1111111111111111111111111111111111111111111111111111111111111111",
          "depends": [1, 2],
          "weight": 400
        }
        """
        let tx = try JSONDecoder().decode(BlockTemplateTransaction.self, from: Data(json.utf8))
        #expect(tx.depends == [1, 2])
        #expect(tx.fee == nil)
        #expect(tx.sigops == nil)
        #expect(tx.weight == 400)
    }

    // MARK: - BlockTemplateRequest (Encodable)

    @Test("BlockTemplateRequest encodes with default rules")
    func blockTemplateRequestEncode() throws {
        let request = BlockTemplateRequest()
        let data = try JSONEncoder().encode(request)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"rules\""))
        #expect(json.contains("\"segwit\""))
    }

    @Test("BlockTemplateRequest encodes proposal mode")
    func blockTemplateRequestProposalEncode() throws {
        let request = BlockTemplateRequest(
            rules: ["segwit"],
            mode: "proposal",
            data: "00000020abcdef"
        )
        let data = try JSONEncoder().encode(request)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"proposal\""))
        #expect(json.contains("\"00000020abcdef\""))
    }
}
