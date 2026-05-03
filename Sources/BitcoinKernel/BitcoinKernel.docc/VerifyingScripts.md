# Verifying Scripts

@Metadata {
    @TitleHeading("How-to Guide")
}

Verify that a transaction input correctly spends a previous output's ``ScriptPubkey`` using the BIP-governed consensus rules wrapped around Bitcoin Core's [`script/interpreter.h`](https://github.com/bitcoin/bitcoin/blob/master/src/script/interpreter.h).

## Running Script Verification

Use ``ScriptPubkey/verify(amount:transaction:precomputedData:inputIndex:flags:)`` to check whether a transaction input satisfies the locking script:

```swift
let script = ScriptPubkey(outputScriptData)
let (valid, status) = script.verify(
    amount: 50_000,
    transaction: spendingTx,
    inputIndex: 0
)

if valid {
    print("Script verification passed")
} else {
    print("Verification failed: \(status)")
}
```

## Understanding Verification Flags

``ScriptVerificationFlags`` controls which consensus rules are applied during verification. Use `.all` for standard mainnet verification:

| Flag | BIP | Description |
|------|-----|-------------|
| ``ScriptVerificationFlags/p2sh`` | [BIP 16](https://github.com/bitcoin/bips/blob/master/bip-0016.mediawiki) | Pay-to-script-hash evaluation |
| ``ScriptVerificationFlags/derSig`` | [BIP 66](https://github.com/bitcoin/bips/blob/master/bip-0066.mediawiki) | Strict DER signature encoding |
| ``ScriptVerificationFlags/nullDummy`` | [BIP 147](https://github.com/bitcoin/bips/blob/master/bip-0147.mediawiki) | Null dummy element for `CHECKMULTISIG` |
| ``ScriptVerificationFlags/checkLockTimeVerify`` | [BIP 65](https://github.com/bitcoin/bips/blob/master/bip-0065.mediawiki) | `OP_CHECKLOCKTIMEVERIFY` |
| ``ScriptVerificationFlags/checkSequenceVerify`` | [BIP 112](https://github.com/bitcoin/bips/blob/master/bip-0112.mediawiki) | `OP_CHECKSEQUENCEVERIFY` |
| ``ScriptVerificationFlags/witness`` | [BIP 141](https://github.com/bitcoin/bips/blob/master/bip-0141.mediawiki) | Segregated Witness |
| ``ScriptVerificationFlags/taproot`` | [BIP 341](https://github.com/bitcoin/bips/blob/master/bip-0341.mediawiki) / [BIP 342](https://github.com/bitcoin/bips/blob/master/bip-0342.mediawiki) | Taproot and Tapscript |

Combine flags using set operations:

```swift
let flags: ScriptVerificationFlags = [.p2sh, .witness, .taproot]
```

## Taproot Verification

Taproot inputs require pre-computed transaction data for efficiency. The pre-computation caches BIP-341 sighash components (`hashPrevouts`, `hashAmounts`, `hashSequences`, `hashOutputs`) that would otherwise be recomputed per input — see [BIP 341 § Signature validation](https://github.com/bitcoin/bips/blob/master/bip-0341.mediawiki#signature-validation) for the hashing algorithm.

```swift
let precomputed = try PrecomputedTransactionData(
    transaction: spendingTx,
    spentOutputs: spentOutputs
)

let (valid, status) = script.verify(
    amount: amount,
    transaction: spendingTx,
    precomputedData: precomputed,
    inputIndex: 0,
    flags: .all
)
```

## Interpreting Results

``ScriptVerifyStatus`` indicates the outcome:

- ``ScriptVerifyStatus/ok`` -- Verification passed (or failed due to script logic).
- ``ScriptVerifyStatus/errorInvalidFlagsCombination`` -- The flags combination is not valid.
- ``ScriptVerifyStatus/errorSpentOutputsRequired`` -- Witness or taproot flags require spent outputs data.

## See Also

- <doc:GettingStarted>
- <doc:ValidatingBlocks>
- ``ScriptPubkey``
- ``ScriptVerificationFlags``
