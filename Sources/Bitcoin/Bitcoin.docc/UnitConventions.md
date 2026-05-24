# Unit Conventions

@Metadata {
    @TitleHeading("Explanation")
}

Understand how Bitcoin Core represents monetary amounts, fee rates, and timestamps in JSON-RPC responses.

## Overview

Bitcoin Core's JSON output uses several distinct numeric conventions across its RPC surface, inherited from years of incremental additions to the [`src/rpc/`](https://github.com/bitcoin/bitcoin/tree/master/src/rpc) handlers. The Swift response models mirror those conventions exactly rather than normalizing them — silent normalization would lose precision and surprise developers cross-referencing against `bitcoin-cli` output. This article maps each convention to where it shows up and how the Swift types represent it.

### Monetary amounts

Bitcoin Core uses two conventions for monetary values:

#### BTC decimal (via BTCAmount)

Most wallet and transaction RPCs return amounts as JSON decimals in **BTC**. These are decoded into ``BTCAmount``, which stores the value internally as satoshis (`Int64`) for precision — the same convention Bitcoin Core itself uses in [`src/util/moneystr.h`](https://github.com/bitcoin/bitcoin/blob/master/src/util/moneystr.h), where amounts are serialized from `CAmount` (an `int64_t` satoshi count) into the decimal string the RPC layer returns:

```swift
let amount = BTCAmount(satoshis: 100_000_000) // 1.0 BTC
let fee = BTCAmount(btc: Decimal(string: "0.0001")!)
print(fee.satoshis) // 10000
```

Examples: `WalletTransaction.amount`, `Vout.value`, `TxOut.value`

> Important: Never decode a BTC amount as `Double`. JSON parsers lose precision past 15 significant digits; `Double(0.1) + Double(0.2) != 0.3`, and a wallet RPC returning `0.10000001 BTC` may round-trip as `0.10000000999...`. Always use ``BTCAmount`` or convert via `Decimal`.

#### Satoshis (via Int64)

Per-block statistics and some internal fields use raw **satoshis** as `Int64` — matching the upstream `CAmount` type:

Examples: `BlockStats.avgfee`, `BlockStats.subsidy`, `BlockStats.totalfee`

The ``BlockStats`` doc comment notes: "All amount fields are in **satoshis** (raw `Int64`), not BTC."

### Fee rates

Fee rates appear in two units across different RPCs. The "vB" suffix means *virtual bytes* — the witness-discounted size unit introduced by [BIP 141 SegWit](https://github.com/bitcoin/bips/blob/master/bip-0141.mediawiki). One virtual byte equals four weight units, per BIP 141's weight definition.

| Unit | Where used | Example fields |
|------|-----------|----------------|
| **BTC/kvB** | Network and relay settings | `NetworkInfo.relayfee`, `MempoolInfo.mempoolminfee` |
| **sat/vB** | Block statistics | `BlockStats.avgfeerate`, `BlockStats.minfeerate` |

To convert between them: **1 sat/vB = 0.00001 BTC/kvB**.

The ``SmartFeeEstimate/feerate`` field is in BTC/kvB.

### Timestamps

#### Unix epoch seconds (via UnixTimestamp)

Most time fields use ``UnixTimestamp``, which decodes from `Int64` and provides a `date` property that bridges to [Foundation `Date`](https://developer.apple.com/documentation/foundation/date):

```swift
let block: Block = ...
print(block.time.date) // Foundation Date
```

Examples: `Block.time`, `PeerInfo.lastsend`, `MempoolEntry.time`

#### Special cases

Not all integer time-like fields are ``UnixTimestamp``:

- **`getnettotals.timemillis`** -- Epoch **milliseconds**, uses plain `Int64`
- **`ban_duration`, `time_remaining`** -- **Durations** in seconds, not timestamps, uses plain `Int64`
- **`locktime`** -- Dual-use: block height when < 500,000,000, epoch seconds when >= 500,000,000. The cutoff is set by Bitcoin Core's [`LOCKTIME_THRESHOLD`](https://github.com/bitcoin/bitcoin/blob/master/src/script/script.h) constant and matches the behavior specified in [BIP 65 OP_CHECKLOCKTIMEVERIFY](https://github.com/bitcoin/bips/blob/master/bip-0065.mediawiki). Uses plain `Int64`.
- **Genesis `mediantime`** -- May be `0` as a sentinel for "not set"

### See also

- ``BTCAmount`` -- decoded monetary value
- ``UnixTimestamp`` -- decoded epoch-second timestamp
- [Bitcoin Core `getblockstats` RPC reference](https://developer.bitcoin.org/reference/rpc/getblockstats.html) -- canonical satoshi-unit source
