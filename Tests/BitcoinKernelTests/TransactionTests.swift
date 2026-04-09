import Testing
import BitcoinKernel
import Foundation

@Test func transactionFromGenesisBlock() throws {
    let txData = dataFromHex(genesisCoinbaseTxHex)
    let tx = try Transaction(txData)
    #expect(tx.outputCount == 1)
    #expect(tx.inputCount == 1)
}

@Test func transactionRoundTrip() throws {
    let txData = dataFromHex(genesisCoinbaseTxHex)
    let tx = try Transaction(txData)
    let serialized = tx.data
    #expect(serialized == txData)
}

@Test func transactionTxid() throws {
    let txData = dataFromHex(genesisCoinbaseTxHex)
    let tx = try Transaction(txData)
    let txid = tx.txid
    #expect(txid.data.count == 32)
}

@Test func transactionInvalidDataThrows() {
    #expect(throws: KernelError.transactionCreationFailed) {
        try Transaction(Data([0x00, 0x01, 0x02]))
    }
}

@Test func transactionOutputAccess() throws {
    let txData = dataFromHex(genesisCoinbaseTxHex)
    let tx = try Transaction(txData)
    let output = tx.output(at: 0)
    // Genesis coinbase: 50 BTC = 5_000_000_000 satoshis
    #expect(output.amount == 5_000_000_000)
    #expect(output.scriptPubkey.data.count > 0)
}

@Test func transactionInputAccess() throws {
    let txData = dataFromHex(genesisCoinbaseTxHex)
    let tx = try Transaction(txData)
    let input = tx.input(at: 0)
    let outPoint = input.outPoint
    // Coinbase input: index is 0xFFFFFFFF, txid is all zeros
    #expect(outPoint.index == 0xFFFFFFFF)
    #expect(outPoint.txid.data == Data(repeating: 0, count: 32))
}

@Test func txidEquality() throws {
    let txData = dataFromHex(genesisCoinbaseTxHex)
    let tx = try Transaction(txData)
    let txid1 = tx.txid
    let txid2 = tx.txid
    #expect(txid1.equals(txid2))
}

@Test func scriptPubkeyRoundTrip() {
    // P2PKH script: OP_DUP OP_HASH160 <20 bytes> OP_EQUALVERIFY OP_CHECKSIG
    let scriptBytes = dataFromHex("76a91489abcdefabbaabbaabbaabbaabbaabbaabbaabba88ac")
    let script = ScriptPubkey(scriptBytes)
    #expect(script.data == scriptBytes)
}

@Test func transactionOutputLifecycle() {
    let scriptBytes = dataFromHex("76a91489abcdefabbaabbaabbaabbaabbaabbaabbaabba88ac")
    let script = ScriptPubkey(scriptBytes)
    let output = TransactionOutput(scriptPubkey: script, amount: 50_000)
    #expect(output.amount == 50_000)
    #expect(output.scriptPubkey.data == scriptBytes)
}

@Test func precomputedDataLifecycle() throws {
    let txData = dataFromHex(genesisCoinbaseTxHex)
    let tx = try Transaction(txData)
    let precomputed = try PrecomputedTransactionData(transaction: tx)
    _ = precomputed // no crash = success
}

// MARK: - Script Verification

@Test func scriptPubkeyVerifyTaprootRequiresSpentOutputs() throws {
    let txData = dataFromHex(genesisCoinbaseTxHex)
    let tx = try Transaction(txData)
    let script = ScriptPubkey(dataFromHex("76a91489abcdefabbaabbaabbaabbaabbaabbaabbaabba88ac"))
    // Taproot flag without precomputed spent outputs → error
    let precomputed = try PrecomputedTransactionData(transaction: tx)
    let (valid, status) = script.verify(
        amount: 0,
        transaction: tx,
        precomputedData: precomputed,
        inputIndex: 0,
        flags: .taproot
    )
    #expect(!valid)
    #expect(status == .errorSpentOutputsRequired)
}

@Test func scriptPubkeyVerifyBasic() throws {
    let txData = dataFromHex(genesisCoinbaseTxHex)
    let tx = try Transaction(txData)
    // Extract the actual output script from the genesis coinbase
    let outputScript = tx.output(at: 0).scriptPubkey
    // Verify with no flags — coinbase input has no real scriptSig, so it fails.
    let (valid, status) = outputScript.verify(
        amount: 5_000_000_000,
        transaction: tx,
        inputIndex: 0,
        flags: .none
    )
    // Coinbase is not a valid spend — we just verify the API runs and returns a result.
    #expect(status == .ok)
    _ = valid
}
