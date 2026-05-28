//
//  BlockchainModelTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
import Foundation
@testable import Bitcoin

/// Heterogeneous JSON value for decoding upstream test vectors (e.g. blockfilters.json).
private enum JSONValue: Codable {
    case int(Int)
    case string(String)
    case array([JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON type") }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        }
    }
}

/// Fixture-based decode tests for Phase 1 blockchain models.
/// Each test uses inline JSON matching Bitcoin Core v31.x regtest output.
@Suite("Blockchain Model Decoding")
struct BlockchainModelTests {

    // MARK: - Transaction (expanded)

    @Test("Transaction with vin/vout decodes from Core JSON")
    func transactionDecode() throws {
        let json = """
        {
          "txid": "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b",
          "hash": "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b",
          "version": 1,
          "size": 204,
          "vsize": 204,
          "weight": 816,
          "locktime": 0,
          "vin": [{
            "coinbase": "04ffff001d0104455468652054696d65732030332f4a616e2f32303039204368616e63656c6c6f72206f6e206272696e6b206f66207365636f6e64206261696c6f757420666f722062616e6b73",
            "txinwitness": [],
            "sequence": 4294967295
          }],
          "vout": [{
            "value": 50.00000000,
            "n": 0,
            "scriptPubKey": {
              "asm": "04678afdb0fe5548271967f1a67130b7105cd6a828e03909a67962e0ea1f61deb649f6bc3f4cef38c4f35504e51ec112de5c384df7ba0b8d578a4c702b6bf11d5f OP_CHECKSIG",
              "hex": "4104678afdb0fe5548271967f1a67130b7105cd6a828e03909a67962e0ea1f61deb649f6bc3f4cef38c4f35504e51ec112de5c384df7ba0b8d578a4c702b6bf11d5fac",
              "type": "pubkey"
            }
          }]
        }
        """
        let tx = try JSONDecoder().decode(Transaction.self, from: Data(json.utf8))
        #expect(tx.txid == "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b")
        #expect(tx.vin.count == 1)
        #expect(tx.vin[0].coinbase != nil)
        #expect(tx.vin[0].sequence == 4294967295)
        #expect(tx.vout.count == 1)
        #expect(tx.vout[0].value == BTCAmount(satoshis: 5_000_000_000))
        #expect(tx.vout[0].n == 0)
        #expect(tx.vout[0].scriptPubKey.type == "pubkey")
    }

    @Test("Transaction: timestamp-based locktime (≥ 500000000) decodes as Int64")
    func transactionTimestampLocktime() throws {
        let json = """
        {
          "txid": "lttx",
          "hash": "lttx",
          "version": 2,
          "size": 100,
          "vsize": 100,
          "weight": 400,
          "locktime": 1700000000,
          "vin": [],
          "vout": []
        }
        """
        let tx = try JSONDecoder().decode(Transaction.self, from: Data(json.utf8))
        #expect(tx.locktime == 1_700_000_000)
    }

    // MARK: - BlockHeader

    @Test("BlockHeader decodes from Core JSON")
    func blockHeaderDecode() throws {
        let json = """
        {
          "hash": "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f",
          "confirmations": 876000,
          "height": 0,
          "version": 1,
          "versionHex": "00000001",
          "merkleroot": "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b",
          "time": 1231006505,
          "mediantime": 1231006505,
          "nonce": 2083236893,
          "bits": "1d00ffff",
          "difficulty": 1.0,
          "chainwork": "0000000000000000000000000000000000000000000000000000000100010001",
          "nTx": 1,
          "nextblockhash": "00000000839a8e6886ab5951d76f411475428afc90947ee320161bbf18eb6048"
        }
        """
        let header = try JSONDecoder().decode(BlockHeader.self, from: Data(json.utf8))
        #expect(header.height == 0)
        #expect(header.nonce == 2083236893)
        #expect(header.time.seconds == 1231006505)
        #expect(header.nTx == 1)
        #expect(header.previousblockhash == nil)
        #expect(header.nextblockhash != nil)
    }

    // MARK: - Block (verbosity 1)

    @Test("Block decodes from Core JSON (verbosity 1, txid list)")
    func blockDecode() throws {
        let json = """
        {
          "hash": "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f",
          "confirmations": 876000,
          "size": 285,
          "strippedsize": 285,
          "weight": 1140,
          "height": 0,
          "version": 1,
          "versionHex": "00000001",
          "merkleroot": "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b",
          "tx": ["4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b"],
          "time": 1231006505,
          "mediantime": 1231006505,
          "nonce": 2083236893,
          "bits": "1d00ffff",
          "difficulty": 1.0,
          "chainwork": "0000000000000000000000000000000000000000000000000000000100010001",
          "nTx": 1,
          "nextblockhash": "00000000839a8e6886ab5951d76f411475428afc90947ee320161bbf18eb6048"
        }
        """
        let block = try JSONDecoder().decode(Block.self, from: Data(json.utf8))
        #expect(block.height == 0)
        #expect(block.hash == "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f")
        #expect(block.tx.count == 1)
        #expect(block.time.seconds == 1231006505)
        #expect(block.medianTime.seconds == 1231006505)
        #expect(block.nonce == 2083236893)
        #expect(block.strippedSize == 285)
        #expect(block.weight == 1140)
        #expect(block.previousBlockHash == nil)
        #expect(block.nextBlockHash != nil)
        #expect(block.nTx == 1)
    }

    // MARK: - BlockWithTransactions (verbosity 2)

    @Test("BlockWithTransactions decodes from Core JSON (verbosity 2)")
    func blockWithTransactionsDecode() throws {
        let json = """
        {
          "hash": "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f",
          "confirmations": 876000,
          "size": 285,
          "strippedsize": 285,
          "weight": 1140,
          "height": 0,
          "version": 1,
          "versionHex": "00000001",
          "merkleroot": "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b",
          "tx": [{
            "txid": "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b",
            "hash": "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b",
            "version": 1,
            "size": 204,
            "vsize": 204,
            "weight": 816,
            "locktime": 0,
            "vin": [{
              "coinbase": "04ffff001d0104455468652054696d65732030332f4a616e2f32303039",
              "txinwitness": [],
              "sequence": 4294967295
            }],
            "vout": [{
              "value": 50.00000000,
              "n": 0,
              "scriptPubKey": {
                "asm": "04678afdb0 OP_CHECKSIG",
                "hex": "4104678afdb0ac",
                "type": "pubkey"
              }
            }]
          }],
          "time": 1231006505,
          "mediantime": 1231006505,
          "nonce": 2083236893,
          "bits": "1d00ffff",
          "difficulty": 1.0,
          "chainwork": "0000000000000000000000000000000000000000000000000000000100010001",
          "nTx": 1,
          "nextblockhash": "00000000839a8e6886ab5951d76f411475428afc90947ee320161bbf18eb6048"
        }
        """
        let block = try JSONDecoder().decode(BlockWithTransactions.self, from: Data(json.utf8))
        #expect(block.height == 0)
        #expect(block.time.seconds == 1231006505)
        #expect(block.medianTime.seconds == 1231006505)
        #expect(block.nonce == 2083236893)
        #expect(block.tx.count == 1)
        #expect(block.tx[0].txid == "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b")
        #expect(block.tx[0].vin[0].coinbase != nil)
        #expect(block.tx[0].vout[0].value == BTCAmount(satoshis: 5_000_000_000))
        #expect(block.previousBlockHash == nil)
    }

    // MARK: - BlockFilter

    @Test("BlockFilter decodes from Core JSON")
    func blockFilterDecode() throws {
        let json = """
        {"filter":"0000000000000000","header":"0000000000000000000000000000000000000000000000000000000000000000"}
        """
        let filter = try JSONDecoder().decode(BlockFilter.self, from: Data(json.utf8))
        #expect(filter.filter == "0000000000000000")
        #expect(!filter.header.isEmpty)
    }

    // MARK: - BlockFilter (upstream fixture)

    @Test("BlockFilter fields match upstream BIP 158 test vectors")
    func blockFilterUpstreamFixture() throws {
        let url = try #require(
            Bundle.module.url(
                forResource: "blockfilters",
                withExtension: "json",
                subdirectory: "Fixtures"
            ),
            "Missing upstream fixture blockfilters.json"
        )
        let data = try Data(contentsOf: url)

        // Upstream format: [[header_row], [height, hash, block, scripts, prev_header, filter, header, notes], ...]
        let rows = try JSONDecoder().decode([[JSONValue]].self, from: data)
        #expect(rows.count > 1, "Expected data rows beyond header")

        for row in rows.dropFirst() {
            guard row.count >= 7,
                  case .string(let filter) = row[5],
                  case .string(let header) = row[6] else {
                continue
            }

            // Construct getblockfilter-shaped JSON and verify BlockFilter decodes it
            let json = """
            {"filter":"\(filter)","header":"\(header)"}
            """
            let blockFilter = try JSONDecoder().decode(
                BlockFilter.self, from: Data(json.utf8)
            )
            #expect(blockFilter.filter == filter)
            #expect(blockFilter.header == header)
            #expect(!blockFilter.header.isEmpty)
        }
    }

    // MARK: - ChainTip

    @Test("ChainTip array decodes from Core JSON")
    func chainTipDecode() throws {
        let json = """
        [{"height":0,"hash":"000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f","branchlen":0,"status":"active"}]
        """
        let tips = try JSONDecoder().decode([ChainTip].self, from: Data(json.utf8))
        #expect(tips.count == 1)
        #expect(tips[0].status == "active")
        #expect(tips[0].branchlen == 0)
    }

    // MARK: - ChainTxStats

    @Test("ChainTxStats decodes from Core JSON")
    func chainTxStatsDecode() throws {
        let json = """
        {
          "time": 1231006505,
          "txcount": 1,
          "window_final_block_hash": "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f",
          "window_final_block_height": 0,
          "window_block_count": 0
        }
        """
        let stats = try JSONDecoder().decode(ChainTxStats.self, from: Data(json.utf8))
        #expect(stats.time.seconds == 1231006505)
        #expect(stats.txcount == 1)
        #expect(stats.windowBlockCount == 0)
        #expect(stats.txrate == nil)
    }

    // MARK: - TxOut

    @Test("TxOut decodes from Core JSON")
    func txOutDecode() throws {
        let json = """
        {
          "bestblock": "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f",
          "confirmations": 876000,
          "value": 50.00000000,
          "scriptPubKey": {
            "asm": "04678afdb0 OP_CHECKSIG",
            "hex": "4104678afdb0ac",
            "type": "pubkey"
          },
          "coinbase": true
        }
        """
        let txout = try JSONDecoder().decode(TxOut.self, from: Data(json.utf8))
        #expect(txout.value == BTCAmount(satoshis: 5_000_000_000))
        #expect(txout.coinbase == true)
        #expect(txout.confirmations == 876000)
    }

    // MARK: - BlockStats

    @Test("BlockStats decodes from Core JSON")
    func blockStatsDecode() throws {
        let json = """
        {
          "avgfee": 0,
          "avgfeerate": 0,
          "avgtxsize": 0,
          "blockhash": "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f",
          "height": 0,
          "ins": 0,
          "maxfee": 0,
          "maxfeerate": 0,
          "maxtxsize": 0,
          "medianfee": 0,
          "mediantime": 1231006505,
          "mediantxsize": 0,
          "minfee": 0,
          "minfeerate": 0,
          "mintxsize": 0,
          "outs": 1,
          "subsidy": 5000000000,
          "time": 1231006505,
          "totalfee": 0,
          "txs": 1,
          "utxo_increase": 1,
          "utxo_increase_actual": 1,
          "utxo_size_inc": 117,
          "utxo_size_inc_actual": 117,
          "total_out": 0,
          "total_size": 0,
          "total_weight": 0,
          "feerate_percentiles": [0, 0, 0, 0, 0]
        }
        """
        let stats = try JSONDecoder().decode(BlockStats.self, from: Data(json.utf8))
        #expect(stats.height == 0)
        #expect(stats.subsidy == 5_000_000_000)
        #expect(stats.utxoIncrease == 1)
        #expect(stats.utxoIncreaseActual == 1)
        #expect(stats.totalOut == 0)
        #expect(stats.mediantime.seconds == 1231006505)
        #expect(stats.feeratePercentiles?.count == 5)
    }

    // MARK: - BlockStats (upstream fixture)

    @Test("BlockStats decodes all entries from upstream Bitcoin Core fixture")
    func blockStatsUpstreamFixture() throws {
        let url = try #require(
            Bundle.module.url(
                forResource: "rpc_getblockstats",
                withExtension: "json",
                subdirectory: "Fixtures"
            ),
            "Missing upstream fixture rpc_getblockstats.json"
        )
        let data = try Data(contentsOf: url)

        struct FixtureFile: Codable {
            let stats: [BlockStats]
        }
        let fixture = try JSONDecoder().decode(FixtureFile.self, from: data)
        #expect(fixture.stats.count == 3)

        // Entry 0: height 101, coinbase-only block
        let s0 = fixture.stats[0]
        #expect(s0.height == 101)
        #expect(s0.avgfee == 0)
        #expect(s0.txs == 1)
        #expect(s0.subsidy == 5_000_000_000)
        #expect(s0.outs == 2)
        #expect(s0.utxoIncrease == 2)
        #expect(s0.utxoIncreaseActual == 1)
        #expect(s0.totalOut == 0)
        #expect(s0.totalSize == 0)
        #expect(s0.totalWeight == 0)
        #expect(s0.utxoSizeInc == 163)
        #expect(s0.utxoSizeIncActual == 75)
        #expect(s0.feeratePercentiles == [0, 0, 0, 0, 0])

        // Entry 1: height 102, 1 user tx with fee
        let s1 = fixture.stats[1]
        #expect(s1.height == 102)
        #expect(s1.avgfee == 4440)
        #expect(s1.txs == 2)
        #expect(s1.ins == 1)
        #expect(s1.totalOut == 4_999_995_560)
        #expect(s1.totalSize == 222)
        #expect(s1.totalWeight == 888)
        #expect(s1.swTotalSize == 0)
        #expect(s1.swTotalWeight == 0)

        // Entry 2: height 103, 4 user txs with segwit and varied fees
        let s2 = fixture.stats[2]
        #expect(s2.height == 103)
        #expect(s2.avgfee == 21390)
        #expect(s2.txs == 5)
        #expect(s2.ins == 4)
        #expect(s2.swtxs == 4)
        #expect(s2.swTotalSize == 878)
        #expect(s2.swTotalWeight == 2204)
        #expect(s2.feeratePercentiles == [20, 20, 20, 301, 301])
        #expect(s2.minfee == 2880)
        #expect(s2.maxfee == 43200)
        #expect(s2.totalOut == 10_899_908_680)
    }


    // MARK: - TxOutSetInfo

    @Test("TxOutSetInfo decodes from Core JSON")
    func txOutSetInfoDecode() throws {
        let json = """
        {
          "height": 0,
          "bestblock": "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f",
          "txouts": 1,
          "bogosize": 85,
          "muhash": "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
          "total_amount": 50.00000000,
          "transactions": 1,
          "disk_size": 49
        }
        """
        let info = try JSONDecoder().decode(TxOutSetInfo.self, from: Data(json.utf8))
        #expect(info.height == 0)
        #expect(info.txouts == 1)
        #expect(info.totalAmount == BTCAmount(satoshis: 5_000_000_000))
        #expect(info.diskSize == 49)
    }

    // MARK: - ScanTxOutResult

    @Test("ScanTxOutResult decodes from Core JSON")
    func scanTxOutResultDecode() throws {
        let json = """
        {
          "success": true,
          "txouts": 100,
          "height": 500,
          "bestblock": "abcdef",
          "unspents": [{
            "txid": "txid123",
            "vout": 0,
            "scriptPubKey": "76a914abcdef88ac",
            "desc": "addr(1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa)#xyz",
            "amount": 0.01000000,
            "coinbase": false,
            "height": 100
          }],
          "total_amount": 0.01000000
        }
        """
        let result = try JSONDecoder().decode(ScanTxOutResult.self, from: Data(json.utf8))
        #expect(result.success)
        #expect(result.unspents.count == 1)
        #expect(result.unspents[0].amount == BTCAmount(satoshis: 1_000_000))
        #expect(result.totalAmount == BTCAmount(satoshis: 1_000_000))
    }

    // MARK: - ScanTxOutProgress

    @Test("ScanTxOutProgress decodes from Core JSON")
    func scanTxOutProgressDecode() throws {
        let json = """
        {"progress": 42.5}
        """
        let progress = try JSONDecoder().decode(ScanTxOutProgress.self, from: Data(json.utf8))
        #expect(progress.progress == 42.5)
    }

    // MARK: - DeploymentInfo

    @Test("DeploymentInfo decodes from Core JSON")
    func deploymentInfoDecode() throws {
        let json = """
        {
          "hash": "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f",
          "height": 0,
          "deployments": {
            "testdummy": {
              "type": "bip9",
              "active": false,
              "bip9": {
                "status": "defined",
                "start_time": 0,
                "timeout": 9223372036854775807,
                "since": 0,
                "min_activation_height": 0
              }
            },
            "taproot": {
              "type": "buried",
              "active": true,
              "height": 0
            }
          }
        }
        """
        let info = try JSONDecoder().decode(DeploymentInfo.self, from: Data(json.utf8))
        #expect(info.height == 0)
        #expect(info.deployments.count == 2)

        let taproot = try #require(info.deployments["taproot"])
        #expect(taproot.type == "buried")
        #expect(taproot.active)
        #expect(taproot.height == 0)

        let testdummy = try #require(info.deployments["testdummy"])
        #expect(testdummy.type == "bip9")
        #expect(!testdummy.active)
        #expect(testdummy.bip9?.status == "defined")
    }

    // MARK: - TxSpendingPrevout

    @Test("TxSpendingPrevout decodes from Core JSON")
    func txSpendingPrevoutDecode() throws {
        let json = """
        [
          {"txid": "abc123", "vout": 0, "spendingtxid": "def456"},
          {"txid": "abc123", "vout": 1}
        ]
        """
        let results = try JSONDecoder().decode([TxSpendingPrevout].self, from: Data(json.utf8))
        #expect(results.count == 2)
        #expect(results[0].spendingtxid == "def456")
        #expect(results[1].spendingtxid == nil)
    }

    // MARK: - Prevout (verbosity 3)

    @Test("VinWithPrevout decodes from Core JSON")
    func vinWithPrevoutDecode() throws {
        let json = """
        {
          "txid": "abc123",
          "vout": 0,
          "scriptSig": {"asm": "", "hex": ""},
          "sequence": 4294967293,
          "prevout": {
            "generated": false,
            "height": 100,
            "value": 1.50000000,
            "scriptPubKey": {
              "asm": "OP_DUP",
              "hex": "76a914",
              "type": "pubkeyhash",
              "address": "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"
            }
          }
        }
        """
        let vin = try JSONDecoder().decode(VinWithPrevout.self, from: Data(json.utf8))
        let prevout = try #require(vin.prevout)
        #expect(prevout.value == BTCAmount(satoshis: 150_000_000))
        #expect(prevout.height == 100)
        #expect(!prevout.generated)
    }

    // MARK: - BlockWithPrevouts (verbosity 3)

    @Test("BlockWithPrevouts decodes from Core JSON (verbosity 3)")
    func blockWithPrevoutsDecode() throws {
        let json = """
        {
          "hash": "00000000839a8e6886ab5951d76f411475428afc90947ee320161bbf18eb6048",
          "confirmations": 875999,
          "size": 215,
          "strippedsize": 215,
          "weight": 860,
          "height": 1,
          "version": 1,
          "versionHex": "00000001",
          "merkleroot": "0e3e2357e806b6cdb1f70b54c3a3a17b6714ee1f0e68bebb44a74b1efd512098",
          "tx": [{
            "txid": "0e3e2357e806b6cdb1f70b54c3a3a17b6714ee1f0e68bebb44a74b1efd512098",
            "hash": "0e3e2357e806b6cdb1f70b54c3a3a17b6714ee1f0e68bebb44a74b1efd512098",
            "version": 1,
            "size": 134,
            "vsize": 134,
            "weight": 536,
            "locktime": 0,
            "vin": [{
              "coinbase": "04ffff001d0104",
              "txinwitness": [],
              "sequence": 4294967295
            }],
            "vout": [{
              "value": 50.00000000,
              "n": 0,
              "scriptPubKey": {
                "asm": "0496b538e853519c726a2c91e61ec11600ae1390813a627c66fb8be7947be63c OP_CHECKSIG",
                "hex": "410496b538e853519c726a2c91e61ec11600ae1390813a627c66fb8be7947be63cac",
                "type": "pubkey"
              }
            }]
          }],
          "time": 1231469665,
          "mediantime": 1231469665,
          "nonce": 2573394689,
          "bits": "1d00ffff",
          "difficulty": 1.0,
          "chainwork": "0000000000000000000000000000000000000000000000000000000200020002",
          "nTx": 1,
          "previousblockhash": "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f",
          "nextblockhash": "000000006a625f06636b8bb6ac7b960a8d03705d1ace08b1a19da3fdcc99ddbd"
        }
        """
        let block = try JSONDecoder().decode(BlockWithPrevouts.self, from: Data(json.utf8))
        #expect(block.height == 1)
        #expect(block.time.seconds == 1231469665)
        #expect(block.medianTime.seconds == 1231469665)
        #expect(block.nonce == 2573394689)
        #expect(block.tx.count == 1)
        #expect(block.tx[0].vin[0].coinbase != nil)
        #expect(block.tx[0].vin[0].prevout == nil)
        #expect(block.tx[0].vout[0].value == BTCAmount(satoshis: 5_000_000_000))
        #expect(block.previousBlockHash == "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f")
        #expect(block.nextBlockHash != nil)
    }

    @Test("TransactionWithPrevout: timestamp-based locktime decodes as Int64")
    func transactionWithPrevoutTimestampLocktime() throws {
        let json = """
        {
          "txid": "ltprevout",
          "hash": "ltprevout",
          "version": 2,
          "size": 100,
          "vsize": 100,
          "weight": 400,
          "locktime": 1700000000,
          "vin": [],
          "vout": []
        }
        """
        let tx = try JSONDecoder().decode(TransactionWithPrevout.self, from: Data(json.utf8))
        #expect(tx.locktime == 1_700_000_000)
    }

    // MARK: - BlockchainInfo

    @Test("BlockchainInfo decodes from Core JSON (non-pruned)")
    func blockchainInfoDecode() throws {
        let json = """
        {
          "chain": "regtest",
          "blocks": 200,
          "headers": 200,
          "bestblockhash": "0f9188f13cb7b2c71f2a335e3a4fc328bf5beb436012afca590b1a11466e2206",
          "difficulty": 4.656542373906925e-10,
          "time": 1713300000,
          "mediantime": 1713299990,
          "verificationprogress": 1.0,
          "initialblockdownload": false,
          "chainwork": "0000000000000000000000000000000000000000000000000000000000000192",
          "size_on_disk": 58627,
          "pruned": false,
          "warnings": []
        }
        """
        let info = try JSONDecoder().decode(BlockchainInfo.self, from: Data(json.utf8))
        #expect(info.chain == "regtest")
        #expect(info.blocks == 200)
        #expect(info.headers == 200)
        #expect(info.time.seconds == 1713300000)
        #expect(info.mediantime.seconds == 1713299990)
        #expect(info.verificationprogress == 1.0)
        #expect(!info.initialblockdownload)
        #expect(info.sizeOnDisk == 58627)
        #expect(!info.pruned)
        #expect(info.pruneheight == nil)
        #expect(info.automaticPruning == nil)
        #expect(info.pruneTargetSize == nil)
        #expect(info.warnings.isEmpty)
    }

    @Test("BlockchainInfo decodes from Core JSON (pruned)")
    func blockchainInfoPrunedDecode() throws {
        let json = """
        {
          "chain": "main",
          "blocks": 876000,
          "headers": 876000,
          "bestblockhash": "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f",
          "difficulty": 110568145977.78,
          "time": 1713300000,
          "mediantime": 1713299000,
          "verificationprogress": 0.999999,
          "initialblockdownload": false,
          "chainwork": "00000000000000000000000000000000000000009c8e007a3e19b3e0b28a5c07",
          "size_on_disk": 12345678901,
          "pruned": true,
          "pruneheight": 800000,
          "automatic_pruning": true,
          "prune_target_size": 1073741824,
          "warnings": ["Warning: unknown new rules activated (versionbit 28)"]
        }
        """
        let info = try JSONDecoder().decode(BlockchainInfo.self, from: Data(json.utf8))
        #expect(info.chain == "main")
        #expect(info.pruned)
        #expect(info.pruneheight == 800000)
        #expect(info.automaticPruning == true)
        #expect(info.pruneTargetSize == 1073741824)
        #expect(info.warnings.count == 1)
    }

    // MARK: - RPCError

    @Test("RPCError decodes from Core JSON")
    func rpcErrorDecode() throws {
        let json = """
        {"code": -32601, "message": "Method not found"}
        """
        let error = try JSONDecoder().decode(RPCError.self, from: Data(json.utf8))
        #expect(error.code == -32601)
        #expect(error.message == "Method not found")
        #expect(error.data == nil)
    }

    @Test("RPCError decodes with optional data field")
    func rpcErrorWithDataDecode() throws {
        let json = """
        {"code": -1, "message": "Internal error", "data": "stack trace info"}
        """
        let error = try JSONDecoder().decode(RPCError.self, from: Data(json.utf8))
        #expect(error.code == -1)
        #expect(error.message == "Internal error")
        #expect(error.data == "stack trace info")
    }
}
