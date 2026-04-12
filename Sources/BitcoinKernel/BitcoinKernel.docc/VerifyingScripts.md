# Verifying Scripts

@Metadata {
    @TitleHeading("How-to Guide")
}

Verify that a transaction input correctly spends a previous output's script.

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
| ``ScriptVerificationFlags/p2sh`` | BIP 16 | Pay-to-script-hash evaluation |
| ``ScriptVerificationFlags/derSig`` | BIP 66 | Strict DER signature encoding |
| ``ScriptVerificationFlags/nullDummy`` | BIP 147 | Null dummy element for `CHECKMULTISIG` |
| ``ScriptVerificationFlags/checkLockTimeVerify`` | BIP 65 | `OP_CHECKLOCKTIMEVERIFY` |
| ``ScriptVerificationFlags/checkSequenceVerify`` | BIP 112 | `OP_CHECKSEQUENCEVERIFY` |
| ``ScriptVerificationFlags/witness`` | BIP 141 | Segregated Witness |
| ``ScriptVerificationFlags/taproot`` | BIP 341/342 | Taproot and Tapscript |

Combine flags using set operations:

```swift
let flags: ScriptVerificationFlags = [.p2sh, .witness, .taproot]
```

## Taproot Verification

Taproot inputs require pre-computed transaction data for efficiency:

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
