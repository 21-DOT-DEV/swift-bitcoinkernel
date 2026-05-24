//
//  RawTxPSBTUtilModelTests.swift
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

/// Decode tests for Phase 4: Raw Transaction, PSBT, and Util models.
@Suite("Raw Tx + PSBT + Util Model Decoding")
struct RawTxPSBTUtilModelTests {

    // MARK: - DecodedTransaction

    @Test("DecodedTransaction decodes from Core JSON")
    func decodedTransactionDecode() throws {
        let json = """
        {
          "txid": "aabb",
          "hash": "aabb",
          "size": 134,
          "vsize": 134,
          "weight": 536,
          "version": 2,
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
              "asm": "OP_DUP OP_HASH160 abc OP_EQUALVERIFY OP_CHECKSIG",
              "hex": "76a914abc88ac",
              "type": "pubkeyhash"
            }
          }]
        }
        """
        let tx = try JSONDecoder().decode(DecodedTransaction.self, from: Data(json.utf8))
        #expect(tx.txid == "aabb")
        #expect(tx.size == 134)
        #expect(tx.vsize == 134)
        #expect(tx.version == 2)
        #expect(tx.vin.count == 1)
        #expect(tx.vout.count == 1)
        #expect(tx.vout[0].value == BTCAmount(satoshis: 5_000_000_000))
    }

    // MARK: - Core vector: real transaction from rpc_tests.cpp rpc_rawparams

    @Test("Core vector: decoderawtransaction from rpc_tests.cpp — size=193, version=1, locktime=0")
    func coreVectorDecodeRawTransaction() throws {
        // This is the exact JSON output Bitcoin Core produces for the raw tx hex
        // used in rpc_tests.cpp rpc_rawparams:
        // "0100000001a15d57094aa7a21a28cb20b59aab8fc7d1149a3bdbcddba9c622e4f5
        //  f6a99ece010000006c493046022100f93bb0e7d8db7bd46e40132d1f8242026e045f
        //  03a0efe71bbb8e3f475e970d790221009337cd7f1f929f00cc6ff01f03729b069a7c
        //  21b59b1736ddfee5db5946c5da8c0121033b9b137ee87d5a812d6f506efdd37f0aff
        //  a7ffc310711c06c7f3e097c9447c52ffffffff0100e1f505000000001976a9140389
        //  035a9225b3839e2bbf32d826a1e222031fd888ac00000000"
        //
        // Core asserts: size=193, version=1, locktime=0
        let json = """
        {
          "txid": "ef7c0cbf6ba5af68d2ea239bba709b26ff7b0b669571a6e680c823f72c3f1eb7",
          "hash": "ef7c0cbf6ba5af68d2ea239bba709b26ff7b0b669571a6e680c823f72c3f1eb7",
          "version": 1,
          "size": 193,
          "vsize": 193,
          "weight": 772,
          "locktime": 0,
          "vin": [{
            "txid": "ce9ea9f6f5e422c6a9dbcddb3b9a14d1c78fab9ab520cb281aa2a74a09575da1",
            "vout": 1,
            "scriptSig": {
              "asm": "3046022100f93bb0e7d8db7bd46e40132d1f8242026e045f03a0efe71bbb8e3f475e970d790221009337cd7f1f929f00cc6ff01f03729b069a7c21b59b1736ddfee5db5946c5da8c[ALL] 033b9b137ee87d5a812d6f506efdd37f0affa7ffc310711c06c7f3e097c9447c52",
              "hex": "493046022100f93bb0e7d8db7bd46e40132d1f8242026e045f03a0efe71bbb8e3f475e970d790221009337cd7f1f929f00cc6ff01f03729b069a7c21b59b1736ddfee5db5946c5da8c0121033b9b137ee87d5a812d6f506efdd37f0affa7ffc310711c06c7f3e097c9447c52"
            },
            "sequence": 4294967295
          }],
          "vout": [{
            "value": 1.00000000,
            "n": 0,
            "scriptPubKey": {
              "asm": "OP_DUP OP_HASH160 0389035a9225b3839e2bbf32d826a1e222031fd8 OP_EQUALVERIFY OP_CHECKSIG",
              "hex": "76a9140389035a9225b3839e2bbf32d826a1e222031fd888ac",
              "type": "pubkeyhash"
            }
          }]
        }
        """
        let tx = try JSONDecoder().decode(DecodedTransaction.self, from: Data(json.utf8))
        // Core-asserted values from rpc_tests.cpp:
        #expect(tx.size == 193)
        #expect(tx.version == 1)
        #expect(tx.locktime == 0)
        // Additional structural checks:
        #expect(tx.vsize == 193) // legacy tx: vsize == size
        #expect(tx.weight == 772) // legacy tx: weight == size * 4
        #expect(tx.vin.count == 1)
        #expect(tx.vin[0].txid == "ce9ea9f6f5e422c6a9dbcddb3b9a14d1c78fab9ab520cb281aa2a74a09575da1")
        #expect(tx.vin[0].vout == 1)
        #expect(tx.vin[0].scriptSig?.asm.contains("033b9b137ee87d5a812d6f506efdd37f0affa7ffc310711c06c7f3e097c9447c52") == true)
        #expect(tx.vin[0].sequence == 4_294_967_295)
        #expect(tx.vout.count == 1)
        #expect(tx.vout[0].value == BTCAmount(satoshis: 100_000_000)) // 1.0 BTC
        #expect(tx.vout[0].n == 0)
        #expect(tx.vout[0].scriptPubKey.type == "pubkeyhash")
    }

    @Test("DecodedTransaction: timestamp-based locktime (≥ 500000000) decodes as Int64")
    func decodedTransactionTimestampLocktime() throws {
        let json = """
        {
          "txid": "locktimetx",
          "hash": "locktimetx",
          "size": 100,
          "vsize": 100,
          "weight": 400,
          "version": 2,
          "locktime": 1700000000,
          "vin": [],
          "vout": []
        }
        """
        let tx = try JSONDecoder().decode(DecodedTransaction.self, from: Data(json.utf8))
        #expect(tx.locktime == 1_700_000_000)
    }

    // MARK: - RawTransaction

    @Test("RawTransaction: timestamp-based locktime decodes as Int64")
    func rawTransactionTimestampLocktime() throws {
        let json = """
        {
          "txid": "ltraw",
          "hash": "ltraw",
          "size": 100,
          "vsize": 100,
          "weight": 400,
          "version": 2,
          "locktime": 1700000000,
          "vin": [],
          "vout": [],
          "hex": "0200000001"
        }
        """
        let tx = try JSONDecoder().decode(RawTransaction.self, from: Data(json.utf8))
        #expect(tx.locktime == 1_700_000_000)
    }

    @Test("RawTransaction decodes with block context")
    func rawTransactionDecode() throws {
        let json = """
        {
          "txid": "aabb",
          "hash": "aabb",
          "size": 134,
          "vsize": 134,
          "weight": 536,
          "version": 2,
          "locktime": 0,
          "vin": [],
          "vout": [],
          "hex": "0200000001",
          "blockhash": "00000000839a8e6886ab5951d76f411475428afc90947ee320161bbf18eb6048",
          "confirmations": 100,
          "time": 1713300000,
          "blocktime": 1713300000,
          "in_active_chain": true
        }
        """
        let tx = try JSONDecoder().decode(RawTransaction.self, from: Data(json.utf8))
        #expect(tx.hex == "0200000001")
        #expect(tx.blockhash != nil)
        #expect(tx.confirmations == 100)
        #expect(tx.time?.seconds == 1713300000)
        #expect(tx.inActiveChain == true)
    }

    @Test("RawTransaction decodes mempool tx (no block context)")
    func rawTransactionMempoolDecode() throws {
        let json = """
        {
          "txid": "ccdd",
          "hash": "ccdd",
          "size": 200,
          "vsize": 150,
          "weight": 600,
          "version": 2,
          "locktime": 0,
          "vin": [],
          "vout": [],
          "hex": "0200000001abcdef"
        }
        """
        let tx = try JSONDecoder().decode(RawTransaction.self, from: Data(json.utf8))
        #expect(tx.blockhash == nil)
        #expect(tx.confirmations == nil)
        #expect(tx.time == nil)
        #expect(tx.inActiveChain == nil)
    }

    // MARK: - SignedTransaction

    @Test("SignedTransaction decodes complete")
    func signedTransactionDecode() throws {
        let json = """
        {"hex": "0200000001abcdef", "complete": true}
        """
        let signed = try JSONDecoder().decode(SignedTransaction.self, from: Data(json.utf8))
        #expect(signed.hex == "0200000001abcdef")
        #expect(signed.complete)
        #expect(signed.errors == nil)
    }

    @Test("SignedTransaction decodes with errors")
    func signedTransactionErrorsDecode() throws {
        let json = """
        {
          "hex": "0200000001",
          "complete": false,
          "errors": [{
            "txid": "aabb",
            "vout": 0,
            "scriptSig": "",
            "sequence": 4294967295,
            "error": "Input not found or already spent"
          }]
        }
        """
        let signed = try JSONDecoder().decode(SignedTransaction.self, from: Data(json.utf8))
        #expect(!signed.complete)
        #expect(signed.errors?.count == 1)
        #expect(signed.errors?[0].error == "Input not found or already spent")
    }

    // MARK: - MempoolAcceptResult

    @Test("MempoolAcceptResult decodes accepted")
    func mempoolAcceptResultDecode() throws {
        let json = """
        {
          "txid": "aabb",
          "wtxid": "ccdd",
          "allowed": true,
          "vsize": 141,
          "fees": {
            "base": 0.00001000,
            "effective-feerate": 0.00007092,
            "effective-includes": ["aabb"]
          }
        }
        """
        let r = try JSONDecoder().decode(MempoolAcceptResult.self, from: Data(json.utf8))
        #expect(r.allowed == true)
        #expect(r.vsize == 141)
        #expect(r.fees?.base == BTCAmount(satoshis: 1000))
        #expect(r.fees?.effectiveFeerate != nil)
        #expect(r.rejectReason == nil)
    }

    @Test("MempoolAcceptResult decodes rejected")
    func mempoolAcceptRejectedDecode() throws {
        let json = """
        {
          "txid": "aabb",
          "wtxid": "ccdd",
          "allowed": false,
          "reject-reason": "insufficient fee"
        }
        """
        let r = try JSONDecoder().decode(MempoolAcceptResult.self, from: Data(json.utf8))
        #expect(r.allowed == false)
        #expect(r.rejectReason == "insufficient fee")
        #expect(r.fees == nil)
    }

    // MARK: - DecodedScript

    @Test("DecodedScript decodes from Core JSON")
    func decodedScriptDecode() throws {
        let json = """
        {
          "asm": "1 eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
          "type": "witness_v1_taproot",
          "address": "bcrt1pamhwamhwamhwamhwamhwamhwamhwamhwamhwamhwamhwamhwamhqz6nvlh",
          "desc": "rawtr(eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee)#jk7c6kys"
        }
        """
        let ds = try JSONDecoder().decode(DecodedScript.self, from: Data(json.utf8))
        #expect(ds.type == "witness_v1_taproot")
        #expect(ds.address != nil)
        #expect(ds.desc != nil)
        #expect(ds.p2sh == nil)
    }

    @Test("DecodedScript decodes from upstream rpc_decodescript.json fixture")
    func decodedScriptUpstreamFixture() throws {
        let url = try #require(
            Bundle.module.url(
                forResource: "rpc_decodescript",
                withExtension: "json",
                subdirectory: "Fixtures"
            ),
            "rpc_decodescript.json fixture not found"
        )
        let data = try Data(contentsOf: url)
        // File is array of [hex_string, {decoded_fields}] pairs
        let entries = try JSONDecoder().decode([[JSONValue]].self, from: data)
        #expect(entries.count > 0)
        // Verify first entry decodes as DecodedScript
        guard case .object(let fields) = entries[0][1] else {
            Issue.record("Expected object at index 1")
            return
        }
        let fieldData = try JSONEncoder().encode(fields)
        let script = try JSONDecoder().decode(DecodedScript.self, from: fieldData)
        #expect(!script.asm.isEmpty)
        #expect(!script.type.isEmpty)
    }

    // MARK: - SimulateRawTxResult

    @Test("SimulateRawTxResult decodes")
    func simulateRawTxResultDecode() throws {
        let json = """
        {"balance_change": -0.00050000}
        """
        let r = try JSONDecoder().decode(SimulateRawTxResult.self, from: Data(json.utf8))
        #expect(r.balanceChange == BTCAmount(satoshis: -50000))
    }

    // MARK: - PrevTxOut (Encodable)

    @Test("PrevTxOut encodes correctly")
    func prevTxOutEncode() throws {
        let p = PrevTxOut(txid: "aabb", vout: 0, scriptPubKey: "76a914")
        let data = try JSONEncoder().encode(p)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"txid\""))
        #expect(json.contains("\"scriptPubKey\""))
    }

    // MARK: - FinalizedPSBT

    @Test("FinalizedPSBT decodes complete")
    func finalizedPSBTCompleteDecode() throws {
        let json = """
        {"hex": "0200000001abcdef", "complete": true}
        """
        let f = try JSONDecoder().decode(FinalizedPSBT.self, from: Data(json.utf8))
        #expect(f.hex == "0200000001abcdef")
        #expect(f.complete)
        #expect(f.psbt == nil)
    }

    @Test("FinalizedPSBT decodes incomplete")
    func finalizedPSBTIncompleteDecode() throws {
        let json = """
        {"psbt": "cHNidP8BADMBAAAAAREREREREREREREREREREREREfrK3hER", "complete": false}
        """
        let f = try JSONDecoder().decode(FinalizedPSBT.self, from: Data(json.utf8))
        #expect(f.psbt != nil)
        #expect(!f.complete)
        #expect(f.hex == nil)
    }

    // MARK: - PSBTAnalysis

    @Test("PSBTAnalysis decodes from Core JSON")
    func psbtAnalysisDecode() throws {
        let json = """
        {
          "inputs": [
            {
              "has_utxo": true,
              "is_final": false,
              "missing": {
                "signatures": ["0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"]
              },
              "next": "signer"
            }
          ],
          "estimated_vsize": 141,
          "estimated_feerate": 0.00007092,
          "fee": 0.00001000,
          "next": "signer"
        }
        """
        let a = try JSONDecoder().decode(PSBTAnalysis.self, from: Data(json.utf8))
        #expect(a.inputs.count == 1)
        #expect(a.inputs[0].hasUtxo)
        #expect(!a.inputs[0].isFinal)
        #expect(a.inputs[0].missing?.signatures?.count == 1)
        #expect(a.estimatedVsize == 141)
        #expect(a.fee == BTCAmount(satoshis: 1000))
        #expect(a.next == "signer")
        #expect(a.error == nil)
    }

    // MARK: - SmartFeeEstimate

    @Test("SmartFeeEstimate decodes with fee rate")
    func smartFeeEstimateDecode() throws {
        let json = """
        {"feerate": 0.00012345, "blocks": 6}
        """
        let e = try JSONDecoder().decode(SmartFeeEstimate.self, from: Data(json.utf8))
        #expect(e.feerate == 0.00012345)
        #expect(e.blocks == 6)
        #expect(e.errors == nil)
    }

    @Test("SmartFeeEstimate decodes with errors (no fee rate)")
    func smartFeeEstimateErrorDecode() throws {
        let json = """
        {"errors": ["Insufficient data or no feerate found"], "blocks": 1008}
        """
        let e = try JSONDecoder().decode(SmartFeeEstimate.self, from: Data(json.utf8))
        #expect(e.feerate == nil)
        #expect(e.errors?.count == 1)
        #expect(e.blocks == 1008)
    }

    // MARK: - AddressValidation

    @Test("AddressValidation decodes valid address")
    func addressValidationValidDecode() throws {
        let json = """
        {
          "isvalid": true,
          "address": "bc1q09vm5lfy0j5reeulh4x5752q25uqqvz34hufdl",
          "scriptPubKey": "0014795b74f490f950f39e7ef753537452155c0030a3",
          "isscript": false,
          "iswitness": true,
          "witness_version": 0,
          "witness_program": "795b74f490f950f39e7ef753537452155c0030a3"
        }
        """
        let v = try JSONDecoder().decode(AddressValidation.self, from: Data(json.utf8))
        #expect(v.isvalid)
        #expect(v.iswitness == true)
        #expect(v.witnessVersion == 0)
        #expect(v.witnessProgram != nil)
    }

    @Test("AddressValidation decodes invalid address")
    func addressValidationInvalidDecode() throws {
        let json = """
        {"isvalid": false}
        """
        let v = try JSONDecoder().decode(AddressValidation.self, from: Data(json.utf8))
        #expect(!v.isvalid)
        #expect(v.address == nil)
        #expect(v.scriptPubKey == nil)
    }

    // MARK: - MultisigResult

    @Test("MultisigResult decodes from Core JSON")
    func multisigResultDecode() throws {
        let json = """
        {
          "address": "2N3sVXU7MZefmYnZhrVX2bA7LyH6vygFZZ7",
          "redeemScript": "522102aabb",
          "descriptor": "sh(multi(2,02aabb,02ccdd))#checksum"
        }
        """
        let m = try JSONDecoder().decode(MultisigResult.self, from: Data(json.utf8))
        #expect(m.address == "2N3sVXU7MZefmYnZhrVX2bA7LyH6vygFZZ7")
        #expect(!m.redeemScript.isEmpty)
        #expect(m.descriptor.contains("multi"))
    }

    // MARK: - DescriptorInfo

    @Test("DescriptorInfo decodes from Core JSON")
    func descriptorInfoDecode() throws {
        let json = """
        {
          "descriptor": "wpkh([d34db33f/84h/0h/0h]0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798)#n9g43y06",
          "checksum": "n9g43y06",
          "isrange": false,
          "issolvable": true,
          "hasprivatekeys": false
        }
        """
        let d = try JSONDecoder().decode(DescriptorInfo.self, from: Data(json.utf8))
        #expect(d.checksum == "n9g43y06")
        #expect(!d.isrange)
        #expect(d.issolvable)
        #expect(!d.hasprivatekeys)
    }

    // MARK: - IndexInfo

    @Test("IndexInfo decodes as dictionary")
    func indexInfoDecode() throws {
        let json = """
        {
          "txindex": {"synced": true, "best_block_height": 876000},
          "coinstatsindex": {"synced": false, "best_block_height": 800000}
        }
        """
        let info = try JSONDecoder().decode([String: IndexInfo].self, from: Data(json.utf8))
        #expect(info.count == 2)
        #expect(info["txindex"]?.synced == true)
        #expect(info["txindex"]?.bestBlockHeight == 876000)
        #expect(info["coinstatsindex"]?.synced == false)
    }
}

// MARK: - JSONValue helper (reused from BlockchainModelTests for fixture parsing)

private enum JSONValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Int.self) { self = .int(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? container.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}
