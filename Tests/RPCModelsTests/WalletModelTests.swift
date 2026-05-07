//
//  WalletModelTests.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
import Foundation
@testable import RPCModels

/// Decode tests for Wallet models.
@Suite("Wallet Model Decoding")
struct WalletModelTests {

    // MARK: - WalletInfo

    @Test("WalletInfo decodes v31 descriptor wallet with all fields")
    func walletInfoDescriptorWallet() throws {
        let json = """
        {
          "walletname": "mywallet",
          "walletversion": 169900,
          "format": "sqlite",
          "txcount": 42,
          "keypoolsize": 4000,
          "keypoolsize_hd_internal": 4000,
          "private_keys_enabled": true,
          "avoid_reuse": false,
          "scanning": false,
          "descriptors": true,
          "external_signer": false,
          "blank": false,
          "birthtime": 1700000000,
          "flags": ["avoid_reuse"],
          "lastprocessedblock": {"hash": "00000000aabb", "height": 800000}
        }
        """
        let info = try JSONDecoder().decode(WalletInfo.self, from: Data(json.utf8))
        #expect(info.walletname == "mywallet")
        #expect(info.walletversion == 169900)
        #expect(info.format == "sqlite")
        #expect(info.txcount == 42)
        #expect(info.descriptors == true)
        #expect(info.avoid_reuse == false)
        #expect(info.private_keys_enabled == true)
        #expect(info.keypoolsize == 4000)
        #expect(info.keypoolsize_hd_internal == 4000)
        #expect(info.unlocked_until == nil)
        #expect(info.external_signer == false)
        #expect(info.blank == false)
        #expect(info.birthtime == 1700000000)
        #expect(info.flags == ["avoid_reuse"])
        #expect(info.lastprocessedblock.hash == "00000000aabb")
        #expect(info.lastprocessedblock.height == 800000)
    }

    @Test("WalletInfo decodes minimal watch-only wallet")
    func walletInfoWatchOnly() throws {
        let json = """
        {
          "walletname": "watch",
          "walletversion": 169900,
          "format": "sqlite",
          "txcount": 0,
          "private_keys_enabled": false,
          "avoid_reuse": false,
          "descriptors": true,
          "external_signer": false,
          "blank": true,
          "flags": [],
          "lastprocessedblock": {"hash": "00000000ccdd", "height": 0}
        }
        """
        let info = try JSONDecoder().decode(WalletInfo.self, from: Data(json.utf8))
        #expect(info.walletname == "watch")
        #expect(info.private_keys_enabled == false)
        #expect(info.keypoolsize == nil)
        #expect(info.blank == true)
        #expect(info.birthtime == nil)
        #expect(info.flags.isEmpty)
    }

    // MARK: - WalletBalances

    @Test("WalletBalances decodes v31 mine-only balances")
    func walletBalancesMineOnly() throws {
        let json = """
        {
          "mine": {
            "trusted": 1.25000000,
            "untrusted_pending": 0.10000000,
            "immature": 0.00000000
          },
          "lastprocessedblock": {"hash": "00000000aabb", "height": 800000}
        }
        """
        let balances = try JSONDecoder().decode(WalletBalances.self, from: Data(json.utf8))
        #expect(balances.mine.trusted == BTCAmount(satoshis: 125_000_000))
        #expect(balances.mine.untrusted_pending == BTCAmount(satoshis: 10_000_000))
        #expect(balances.mine.immature == BTCAmount.zero)
        #expect(balances.mine.used == nil)
        #expect(balances.lastprocessedblock.hash == "00000000aabb")
        #expect(balances.lastprocessedblock.height == 800000)
    }

    @Test("WalletBalances decodes with used field (avoid_reuse)")
    func walletBalancesWithUsed() throws {
        let json = """
        {
          "mine": {
            "trusted": 5.00000000,
            "untrusted_pending": 0.00000000,
            "immature": 50.00000000,
            "used": 0.50000000
          },
          "lastprocessedblock": {"hash": "00000000eeff", "height": 900000}
        }
        """
        let balances = try JSONDecoder().decode(WalletBalances.self, from: Data(json.utf8))
        #expect(balances.mine.trusted == BTCAmount(satoshis: 500_000_000))
        #expect(balances.mine.used == BTCAmount(satoshis: 50_000_000))
    }

    // MARK: - WalletTransaction

    @Test("WalletTransaction decodes confirmed receive")
    func walletTransactionReceive() throws {
        let json = """
        {
          "amount": 0.50000000,
          "confirmations": 6,
          "blockhash": "00000000000000000001aabb",
          "blockheight": 800000,
          "blocktime": 1700000000,
          "txid": "deadbeef1234",
          "walletconflicts": [],
          "time": 1699999000,
          "timereceived": 1699999100,
          "details": [{
            "category": "receive",
            "amount": 0.50000000,
            "address": "bc1qtest",
            "label": "donations",
            "vout": 0
          }],
          "hex": "0100000001..."
        }
        """
        let tx = try JSONDecoder().decode(WalletTransaction.self, from: Data(json.utf8))
        #expect(tx.amount == BTCAmount(satoshis: 50_000_000))
        #expect(tx.confirmations == 6)
        #expect(tx.blockhash == "00000000000000000001aabb")
        #expect(tx.blockheight == 800000)
        #expect(tx.txid == "deadbeef1234")
        #expect(tx.fee == nil)
        #expect(tx.details?.count == 1)
        #expect(tx.details?[0].category == "receive")
        #expect(tx.details?[0].address == "bc1qtest")
        #expect(tx.details?[0].label == "donations")
        #expect(tx.details?[0].vout == 0)
        #expect(tx.details?[0].fee == nil)
        #expect(tx.details?[0].abandoned == nil)
    }

    @Test("WalletTransaction decodes unconfirmed send with fee")
    func walletTransactionSend() throws {
        let json = """
        {
          "amount": -0.10000000,
          "fee": -0.00001500,
          "confirmations": 0,
          "txid": "aabbccdd",
          "time": 1700000000,
          "timereceived": 1700000000,
          "details": [{
            "category": "send",
            "amount": -0.10000000,
            "address": "bc1qrecipient",
            "vout": 0,
            "fee": -0.00001500,
            "abandoned": false
          }]
        }
        """
        let tx = try JSONDecoder().decode(WalletTransaction.self, from: Data(json.utf8))
        #expect(tx.amount == BTCAmount(satoshis: -10_000_000))
        #expect(tx.fee == BTCAmount(satoshis: -1_500))
        #expect(tx.confirmations == 0)
        #expect(tx.blockhash == nil)
        #expect(tx.details?[0].category == "send")
        #expect(tx.details?[0].fee == BTCAmount(satoshis: -1_500))
        #expect(tx.details?[0].abandoned == false)
    }

    // MARK: - CreateWalletResult

    @Test("CreateWalletResult decodes success with no warnings")
    func createWalletSuccess() throws {
        let json = """
        {"name": "newwallet", "warnings": []}
        """
        let result = try JSONDecoder().decode(CreateWalletResult.self, from: Data(json.utf8))
        #expect(result.name == "newwallet")
        #expect(result.warnings?.isEmpty == true)
        #expect(result.warning == nil)
    }

    @Test("CreateWalletResult decodes with warning string (legacy format)")
    func createWalletLegacyWarning() throws {
        let json = """
        {"name": "oldwallet", "warning": "Wallet loaded with some deprecation warnings"}
        """
        let result = try JSONDecoder().decode(CreateWalletResult.self, from: Data(json.utf8))
        #expect(result.name == "oldwallet")
        #expect(result.warning?.contains("deprecation") == true)
    }

    // MARK: - BumpFeeResult

    @Test("BumpFeeResult decodes fee bump")
    func bumpFeeResult() throws {
        let json = """
        {
          "txid": "newtxid1234",
          "origfee": 0.00001000,
          "fee": 0.00005000,
          "errors": []
        }
        """
        let result = try JSONDecoder().decode(BumpFeeResult.self, from: Data(json.utf8))
        #expect(result.txid == "newtxid1234")
        #expect(result.origfee == BTCAmount(satoshis: 1_000))
        #expect(result.fee == BTCAmount(satoshis: 5_000))
        #expect(result.errors?.isEmpty == true)
    }

    @Test("PSBTBumpFeeResult decodes PSBT bump")
    func psbtBumpFeeResult() throws {
        let json = """
        {
          "psbt": "cHNidFF=",
          "origfee": 0.00001000,
          "fee": 0.00003000,
          "errors": []
        }
        """
        let result = try JSONDecoder().decode(PSBTBumpFeeResult.self, from: Data(json.utf8))
        #expect(result.psbt == "cHNidFF=")
        #expect(result.origfee == BTCAmount(satoshis: 1_000))
        #expect(result.fee == BTCAmount(satoshis: 3_000))
    }

    // MARK: - UnspentOutput

    @Test("UnspentOutput decodes spendable UTXO")
    func unspentOutputSpendable() throws {
        let json = """
        {
          "txid": "utxotxid1234",
          "vout": 0,
          "address": "bc1qtest",
          "label": "savings",
          "scriptPubKey": "0014abc123",
          "amount": 0.25000000,
          "confirmations": 144,
          "spendable": true,
          "solvable": true,
          "desc": "wpkh([abc/84h/0h/0h]xpub.../0/0)#checksum",
          "safe": true
        }
        """
        let utxo = try JSONDecoder().decode(UnspentOutput.self, from: Data(json.utf8))
        #expect(utxo.txid == "utxotxid1234")
        #expect(utxo.vout == 0)
        #expect(utxo.address == "bc1qtest")
        #expect(utxo.label == "savings")
        #expect(utxo.scriptPubKey == "0014abc123")
        #expect(utxo.amount == BTCAmount(satoshis: 25_000_000))
        #expect(utxo.confirmations == 144)
        #expect(utxo.spendable == true)
        #expect(utxo.solvable == true)
        #expect(utxo.safe == true)
        #expect(utxo.redeemScript == nil)
        #expect(utxo.witnessScript == nil)
        #expect(utxo.reused == nil)
    }

    @Test("UnspentOutput decodes watch-only UTXO")
    func unspentOutputWatchOnly() throws {
        let json = """
        {
          "txid": "watchtxid",
          "vout": 1,
          "scriptPubKey": "76a914abc88ac",
          "amount": 1.00000000,
          "confirmations": 10,
          "spendable": false,
          "solvable": false,
          "safe": true
        }
        """
        let utxo = try JSONDecoder().decode(UnspentOutput.self, from: Data(json.utf8))
        #expect(utxo.spendable == false)
        #expect(utxo.solvable == false)
        #expect(utxo.address == nil)
        #expect(utxo.amount == BTCAmount(satoshis: 100_000_000))
    }

    @Test("UnspentOutput decodes mempool UTXO with ancestor fields (ancestorfees as satoshis)")
    func unspentOutputMempoolAncestors() throws {
        let json = """
        {
          "txid": "mempooltxid",
          "vout": 0,
          "address": "bc1qmempool",
          "scriptPubKey": "0014def456",
          "amount": 0.01000000,
          "confirmations": 0,
          "ancestorcount": 2,
          "ancestorsize": 450,
          "ancestorfees": 4440,
          "spendable": true,
          "solvable": true,
          "desc": "wpkh(xpub...)#check",
          "safe": true
        }
        """
        let utxo = try JSONDecoder().decode(UnspentOutput.self, from: Data(json.utf8))
        #expect(utxo.confirmations == 0)
        #expect(utxo.ancestorcount == 2)
        #expect(utxo.ancestorsize == 450)
        // ancestorfees is raw satoshis (CAmount), NOT BTC decimal
        #expect(utxo.ancestorfees == 4440)
    }

    // MARK: - SendResult

    @Test("SendResult decodes complete send with txid")
    func sendResultComplete() throws {
        let json = """
        {
          "complete": true,
          "txid": "finaltxid",
          "hex": "0100000001..."
        }
        """
        let result = try JSONDecoder().decode(SendResult.self, from: Data(json.utf8))
        #expect(result.complete == true)
        #expect(result.txid == "finaltxid")
        #expect(result.hex == "0100000001...")
        #expect(result.psbt == nil)
    }

    @Test("SendResult decodes incomplete send with PSBT")
    func sendResultIncomplete() throws {
        let json = """
        {
          "complete": false,
          "psbt": "cHNidFF="
        }
        """
        let result = try JSONDecoder().decode(SendResult.self, from: Data(json.utf8))
        #expect(result.complete == false)
        #expect(result.txid == nil)
        #expect(result.hex == nil)
        #expect(result.psbt == "cHNidFF=")
    }

    // MARK: - ListSinceBlockResult

    @Test("ListSinceBlockResult decodes with transactions")
    func listSinceBlockWithTxs() throws {
        let json = """
        {
          "transactions": [{
            "address": "bc1qtest",
            "category": "receive",
            "amount": 0.10000000,
            "vout": 0,
            "confirmations": 3,
            "blockhash": "00000000aabb",
            "blockheight": 800001,
            "blocktime": 1700001000,
            "txid": "sincetxid1",
            "time": 1700000500,
            "timereceived": 1700000600,
            "label": "incoming"
          }],
          "lastblock": "00000000ccdd"
        }
        """
        let result = try JSONDecoder().decode(ListSinceBlockResult.self, from: Data(json.utf8))
        #expect(result.transactions.count == 1)
        #expect(result.lastblock == "00000000ccdd")
        #expect(result.removed == nil)

        let tx = result.transactions[0]
        #expect(tx.address == "bc1qtest")
        #expect(tx.category == "receive")
        #expect(tx.amount == BTCAmount(satoshis: 10_000_000))
        #expect(tx.vout == 0)
        #expect(tx.confirmations == 3)
        #expect(tx.blockhash == "00000000aabb")
        #expect(tx.blockheight == 800001)
        #expect(tx.txid == "sincetxid1")
        #expect(tx.label == "incoming")
        #expect(tx.fee == nil)
        #expect(tx.abandoned == nil)
        #expect(tx.replaced_by_txid == nil)
    }

    @Test("ListSinceBlockResult decodes empty result")
    func listSinceBlockEmpty() throws {
        let json = """
        {
          "transactions": [],
          "removed": [],
          "lastblock": "000000001234"
        }
        """
        let result = try JSONDecoder().decode(ListSinceBlockResult.self, from: Data(json.utf8))
        #expect(result.transactions.isEmpty)
        #expect(result.removed?.isEmpty == true)
        #expect(result.lastblock == "000000001234")
    }

    // MARK: - FundRawTransactionResult

    @Test("FundRawTransactionResult decodes with change output")
    func fundRawTxWithChange() throws {
        let json = """
        {
          "hex": "0200000001aabb...00000000",
          "fee": 0.00001410,
          "changepos": 1
        }
        """
        let result = try JSONDecoder().decode(FundRawTransactionResult.self, from: Data(json.utf8))
        #expect(result.hex == "0200000001aabb...00000000")
        #expect(result.fee == BTCAmount(satoshis: 1_410))
        #expect(result.changepos == 1)
    }

    @Test("FundRawTransactionResult decodes without change (changepos = -1)")
    func fundRawTxNoChange() throws {
        let json = """
        {
          "hex": "0200000001ccdd...00000000",
          "fee": 0.00002500,
          "changepos": -1
        }
        """
        let result = try JSONDecoder().decode(FundRawTransactionResult.self, from: Data(json.utf8))
        #expect(result.fee == BTCAmount(satoshis: 2_500))
        #expect(result.changepos == -1)
    }

    // MARK: - RescanResult

    @Test("RescanResult decodes height range")
    func rescanResult() throws {
        let json = """
        {
          "start_height": 0,
          "stop_height": 800000
        }
        """
        let result = try JSONDecoder().decode(RescanResult.self, from: Data(json.utf8))
        #expect(result.start_height == 0)
        #expect(result.stop_height == 800_000)
    }

    @Test("RescanResult decodes partial range")
    func rescanResultPartial() throws {
        let json = """
        {
          "start_height": 750000,
          "stop_height": 800000
        }
        """
        let result = try JSONDecoder().decode(RescanResult.self, from: Data(json.utf8))
        #expect(result.start_height == 750_000)
        #expect(result.stop_height == 800_000)
    }

    // MARK: - Core vectors: wallet_listtransactions.py

    @Test("Core vector: listtransactions send — category=send, amount=-0.1, confirmations=0 (wallet_listtransactions.py)")
    func coreVectorListTxSend() throws {
        // From wallet_listtransactions.py: sendtoaddress(node1, 0.1) → sender sees:
        //   {"category": "send", "amount": Decimal("-0.1"), "confirmations": 0, "trusted": True}
        let json = """
        {
          "address": "bc1qreceiver",
          "category": "send",
          "amount": -0.10000000,
          "vout": 0,
          "fee": -0.00001000,
          "confirmations": 0,
          "txid": "sendtxid",
          "time": 1700000000,
          "timereceived": 1700000000,
          "abandoned": false
        }
        """
        let detail = try JSONDecoder().decode(WalletTransactionDetail.self, from: Data(json.utf8))
        #expect(detail.category == "send")
        #expect(detail.amount == BTCAmount(satoshis: -10_000_000))
        #expect(detail.fee == BTCAmount(satoshis: -1_000))
        #expect(detail.abandoned == false)
    }

    @Test("Core vector: listtransactions receive — category=receive, amount=0.1, confirmations=0 (wallet_listtransactions.py)")
    func coreVectorListTxReceive() throws {
        // From wallet_listtransactions.py: receiver sees:
        //   {"category": "receive", "amount": Decimal("0.1"), "confirmations": 0, "trusted": False}
        let json = """
        {
          "address": "bc1qreceiver",
          "category": "receive",
          "amount": 0.10000000,
          "vout": 0,
          "confirmations": 0,
          "txid": "recvtxid",
          "time": 1700000000,
          "timereceived": 1700000000
        }
        """
        let detail = try JSONDecoder().decode(WalletTransactionDetail.self, from: Data(json.utf8))
        #expect(detail.category == "receive")
        #expect(detail.amount == BTCAmount(satoshis: 10_000_000))
        #expect(detail.fee == nil)
        #expect(detail.abandoned == nil)
    }

    @Test("Core vector: listtransactions after confirm — confirmations=1, blockhash+blockheight present (wallet_listtransactions.py)")
    func coreVectorListTxConfirmed() throws {
        // From wallet_listtransactions.py:
        //   {"category": "send", "amount": Decimal("-0.1"), "confirmations": 1, "blockhash": blockhash, "blockheight": blockheight}
        let json = """
        {
          "address": "bc1qreceiver",
          "category": "send",
          "amount": -0.10000000,
          "vout": 0,
          "fee": -0.00001000,
          "confirmations": 1,
          "blockhash": "00000000000000000002a7c4c1e48d76c5a37902165a270156b7a8d72f9a68cd",
          "blockheight": 800001,
          "blocktime": 1700001000,
          "txid": "confirmedtxid",
          "time": 1700000000,
          "timereceived": 1700000000,
          "abandoned": false
        }
        """
        let detail = try JSONDecoder().decode(SinceBlockTransaction.self, from: Data(json.utf8))
        #expect(detail.category == "send")
        #expect(detail.amount == BTCAmount(satoshis: -10_000_000))
        #expect(detail.confirmations == 1)
        #expect(detail.blockhash == "00000000000000000002a7c4c1e48d76c5a37902165a270156b7a8d72f9a68cd")
        #expect(detail.blockheight == 800001)
    }

    @Test("Core vector: send-to-self produces both send and receive entries (wallet_listtransactions.py)")
    func coreVectorSendToSelf() throws {
        // From wallet_listtransactions.py: sendtoaddress(self, 0.2) →
        //   send: {"amount": Decimal("-0.2")}
        //   receive: {"amount": Decimal("0.2")}
        let sendJson = """
        {"category": "send", "amount": -0.20000000, "vout": 0, "address": "bc1qself",
         "txid": "selftxid", "time": 1700000000, "timereceived": 1700000000, "confirmations": 0}
        """
        let recvJson = """
        {"category": "receive", "amount": 0.20000000, "vout": 0, "address": "bc1qself",
         "txid": "selftxid", "time": 1700000000, "timereceived": 1700000000, "confirmations": 0}
        """
        let send = try JSONDecoder().decode(SinceBlockTransaction.self, from: Data(sendJson.utf8))
        let recv = try JSONDecoder().decode(SinceBlockTransaction.self, from: Data(recvJson.utf8))
        #expect(send.txid == recv.txid)
        #expect(send.amount == BTCAmount(satoshis: -20_000_000))
        #expect(recv.amount == BTCAmount(satoshis: 20_000_000))
        #expect(send.category == "send")
        #expect(recv.category == "receive")
    }

    // MARK: - Core vectors: wallet_balance.py

    @Test("Core vector: getbalances mine.trusted = 50 BTC after coinbase maturity (wallet_balance.py)")
    func coreVectorCoinbaseBalance() throws {
        // From wallet_balance.py: after COINBASE_MATURITY+1 blocks,
        //   getbalances()["mine"]["trusted"] == 50 (one mature coinbase)
        //   getbalance("*") == 50
        let json = """
        {
          "mine": {
            "trusted": 50.00000000,
            "untrusted_pending": 0.00000000,
            "immature": 0.00000000
          },
          "lastprocessedblock": {"hash": "00000000aabb", "height": 101}
        }
        """
        let balances = try JSONDecoder().decode(WalletBalances.self, from: Data(json.utf8))
        #expect(balances.mine.trusted == BTCAmount(satoshis: 5_000_000_000))
        #expect(balances.mine.untrusted_pending == BTCAmount.zero)
        #expect(balances.mine.immature == BTCAmount.zero)
    }

    @Test("Core vector: getbalances after 40+60 BTC cross-send (wallet_balance.py)")
    func coreVectorCrossSendBalance() throws {
        // From wallet_balance.py: after sending 40 BTC and receiving 60 BTC,
        //   node0: mine.trusted = 69.99 (50 - 40 + 60 - 0.01 fee)
        //   node1: mine.trusted = 29.98 (50 - 60 + 40 - 0.01 fee * 2)
        let json0 = """
        {"mine": {"trusted": 69.99000000, "untrusted_pending": 0.00000000, "immature": 0.00000000},
         "lastprocessedblock": {"hash": "00000000a1", "height": 102}}
        """
        let json1 = """
        {"mine": {"trusted": 29.98000000, "untrusted_pending": 0.00000000, "immature": 0.00000000},
         "lastprocessedblock": {"hash": "00000000a1", "height": 102}}
        """
        let b0 = try JSONDecoder().decode(WalletBalances.self, from: Data(json0.utf8))
        let b1 = try JSONDecoder().decode(WalletBalances.self, from: Data(json1.utf8))
        #expect(b0.mine.trusted == BTCAmount(satoshis: 6_999_000_000))
        #expect(b1.mine.trusted == BTCAmount(satoshis: 2_998_000_000))
    }

    // MARK: - Core vectors: wallet_listsinceblock.py

    @Test("Core vector: listsinceblock returns lastblock=blockhash, removed=[] (wallet_listsinceblock.py)")
    func coreVectorListSinceBlockStructure() throws {
        // From wallet_listsinceblock.py:
        //   assert_equal(nodes[0].listsinceblock(),
        //     {"lastblock": blockhash, "removed": [], "transactions": txs})
        let json = """
        {
          "transactions": [{
            "address": "bc1qtest",
            "category": "receive",
            "amount": 1.00000000,
            "vout": 0,
            "confirmations": 1,
            "blockhash": "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f",
            "blockheight": 101,
            "blocktime": 1231469665,
            "txid": "sinceblocktxid",
            "time": 1231469600,
            "timereceived": 1231469610
          }],
          "removed": [],
          "lastblock": "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"
        }
        """
        let result = try JSONDecoder().decode(ListSinceBlockResult.self, from: Data(json.utf8))
        #expect(result.lastblock == "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f")
        #expect(result.removed?.isEmpty == true)
        #expect(result.transactions.count == 1)
        #expect(result.transactions[0].amount == BTCAmount(satoshis: 100_000_000))
        #expect(result.transactions[0].confirmations == 1)
        #expect(result.transactions[0].blockheight == 101)
    }

    @Test("Core vector: listsinceblock reorg — removed tx still has confirmations=2 (wallet_listsinceblock.py)")
    func coreVectorListSinceBlockReorg() throws {
        // From wallet_listsinceblock.py: after reorg, removed tx:
        //   for tx in lsbres['removed']: assert_equal(tx['confirmations'], 2)
        let json = """
        {
          "transactions": [{
            "address": "bc1qtest",
            "category": "receive",
            "amount": 1.00000000,
            "vout": 0,
            "confirmations": 2,
            "blockhash": "00000000aabb",
            "blockheight": 103,
            "blocktime": 1231470000,
            "txid": "reorgtxid",
            "time": 1231469900,
            "timereceived": 1231469910
          }],
          "removed": [{
            "address": "bc1qtest",
            "category": "receive",
            "amount": 1.00000000,
            "vout": 0,
            "confirmations": 2,
            "blockhash": "00000000ccdd",
            "blockheight": 103,
            "blocktime": 1231470000,
            "txid": "reorgtxid",
            "time": 1231469900,
            "timereceived": 1231469910
          }],
          "lastblock": "00000000eeff"
        }
        """
        let result = try JSONDecoder().decode(ListSinceBlockResult.self, from: Data(json.utf8))
        #expect(result.removed?.count == 1)
        #expect(result.removed?[0].confirmations == 2)
        #expect(result.removed?[0].txid == "reorgtxid")
        #expect(result.transactions[0].txid == result.removed?[0].txid)
    }

    // MARK: - Core vectors: wallet_bumpfee.py

    @Test("Core vector: bumpfee — errors=[], fee > origfee, no psbt field (wallet_bumpfee.py)")
    func coreVectorBumpFee() throws {
        // From wallet_bumpfee.py:
        //   assert_equal(bumped_tx["errors"], [])
        //   assert bumped_tx["fee"] > -rbftx["fee"]
        //   assert_equal(bumped_tx["origfee"], -rbftx["fee"])
        //   assert "psbt" not in bumped_tx
        let json = """
        {
          "txid": "bumpedtxid1234",
          "origfee": 0.00001000,
          "fee": 0.00005000,
          "errors": []
        }
        """
        let result = try JSONDecoder().decode(BumpFeeResult.self, from: Data(json.utf8))
        #expect(result.errors?.isEmpty == true)
        #expect(result.fee > result.origfee)
        #expect(result.origfee == BTCAmount(satoshis: 1_000))
        #expect(result.fee == BTCAmount(satoshis: 5_000))
        #expect(result.txid == "bumpedtxid1234")
    }

    @Test("Core vector: psbtbumpfee — errors=[], fee > origfee, psbt present (wallet_bumpfee.py)")
    func coreVectorPSBTBumpFee() throws {
        // From wallet_bumpfee.py:
        //   assert_equal(bumped_psbt["errors"], [])
        //   assert bumped_psbt["fee"] > -rbftx["fee"]
        //   assert_equal(bumped_psbt["origfee"], -rbftx["fee"])
        //   assert "psbt" in bumped_psbt
        let json = """
        {
          "psbt": "cHNidC1idW1wZmVl",
          "origfee": 0.00001000,
          "fee": 0.00005000,
          "errors": []
        }
        """
        let result = try JSONDecoder().decode(PSBTBumpFeeResult.self, from: Data(json.utf8))
        #expect(result.errors?.isEmpty == true)
        #expect(result.fee > result.origfee)
        #expect(result.origfee == BTCAmount(satoshis: 1_000))
        #expect(!result.psbt.isEmpty)
    }

    // MARK: - Core vectors: wallet_balance.py (sendmany amounts)

    @Test("Core vector: sendmany amounts -0.11, -0.22, -0.33, -0.44 (wallet_listtransactions.py)")
    func coreVectorSendManyAmounts() throws {
        // From wallet_listtransactions.py: sendmany with 0.11, 0.22, 0.33, 0.44 →
        //   sender sees send entries with negative amounts
        let amounts: [Double] = [-0.11, -0.22, -0.33, -0.44]
        let expectedSats: [Int64] = [-11_000_000, -22_000_000, -33_000_000, -44_000_000]

        for (amount, sats) in zip(amounts, expectedSats) {
            let json = """
            {"category": "send", "amount": \(amount), "vout": 0, "address": "bc1q",
             "txid": "sendmanytx", "time": 1700000000, "timereceived": 1700000000, "confirmations": 0}
            """
            let tx = try JSONDecoder().decode(SinceBlockTransaction.self, from: Data(json.utf8))
            #expect(tx.amount == BTCAmount(satoshis: sats))
            #expect(tx.category == "send")
        }
    }
}
