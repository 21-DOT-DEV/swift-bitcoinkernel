# Verifying Scripts

@Metadata {
    @TitleHeading("How-to Guide")
}

Verify that a transaction input correctly spends a previous output's ``ScriptPubkey`` using the BIP-governed consensus rules wrapped around Bitcoin Core's [`script/interpreter.h`](https://github.com/bitcoin/bitcoin/blob/master/src/script/interpreter.h).

## Overview

Verification in BitcoinKernel runs an input's witness and `scriptSig` against the locking program from the previous output, producing a pass/fail outcome plus a status enum describing why. The opcode evaluator is `libbitcoinkernel`'s consensus-critical interpreter — the same code path consensus uses — so a "pass" here matches what a fully-validating node accepts.

The article covers four things in this order: running a verification, picking the right flag set, the additional setup taproot inputs require, and how to interpret the status enum.

## Running verification

Use ``ScriptPubkey/verify(amount:transaction:precomputedData:inputIndex:flags:)`` to check whether a transaction input satisfies the locking program:

```swift
let pubkey = ScriptPubkey(outputScriptData)
let (valid, status) = pubkey.verify(
    amount: 50_000,
    transaction: spendingTx,
    inputIndex: 0
)

if valid {
    print("Verification passed")
} else {
    print("Verification failed: \(status)")
}
```

> Important: The `amount` parameter must be the value (in satoshis) of the previous output being spent — not the output being created. Passing the wrong value silently invalidates SegWit-style sighashes because amount is committed to via [BIP 143](https://github.com/bitcoin/bips/blob/master/bip-0143.mediawiki).

## Picking flags

``ScriptVerificationFlags`` controls which consensus rules apply during evaluation. Use `.all` for standard mainnet behavior:

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

A historically-accurate replay (validating pre-SegWit blocks against pre-SegWit rules) requires excluding `.witness` and `.taproot` for the era in question. For most modern callers, `.all` is the correct choice.

## Taproot inputs

Taproot inputs require pre-computed transaction data for efficiency. The pre-computation caches BIP-341 sighash components (`hashPrevouts`, `hashAmounts`, `hashSequences`, `hashOutputs`) that would otherwise be recomputed per input — see [BIP 341 § Signature validation](https://github.com/bitcoin/bips/blob/master/bip-0341.mediawiki#signature-validation) for the hashing algorithm.

```swift
let precomputed = try PrecomputedTransactionData(
    transaction: spendingTx,
    spentOutputs: spentOutputs
)

let (valid, status) = pubkey.verify(
    amount: amount,
    transaction: spendingTx,
    precomputedData: precomputed,
    inputIndex: 0,
    flags: .all
)
```

The `spentOutputs` array must contain every previous output the transaction spends, in input order. The interpreter binds them into the sighash; passing the wrong subset surfaces as ``ScriptVerifyStatus/errorSpentOutputsRequired``.

## Interpreting results

``ScriptVerifyStatus`` indicates the outcome:

- ``ScriptVerifyStatus/ok`` -- Verification passed (or failed due to script logic).
- ``ScriptVerifyStatus/errorInvalidFlagsCombination`` -- The flags combination is not valid.
- ``ScriptVerifyStatus/errorSpentOutputsRequired`` -- Witness or taproot flags require spent outputs data.

## See Also

- <doc:GettingStarted>
- <doc:ValidatingBlocks>
- ``ScriptPubkey``
- ``ScriptVerificationFlags``
