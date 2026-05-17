# Unit Conventions

@Metadata {
    @TitleHeading("Explanation")
}

Understand how Bitcoin Core represents monetary amounts, fee rates, and timestamps in JSON-RPC responses.

## Monetary Amounts

Bitcoin Core uses two conventions for monetary amounts:

### BTC Decimal (via BTCAmount)

Most wallet and transaction RPCs return amounts as JSON decimals in **BTC**. These are decoded into ``BTCAmount``, which stores the value internally as satoshis (`Int64`) for precision:

```swift
let amount = BTCAmount(satoshis: 100_000_000) // 1.0 BTC
let fee = BTCAmount(btc: Decimal(string: "0.0001")!)
print(fee.satoshis) // 10000
```

Examples: `WalletTransaction.amount`, `Vout.value`, `TxOut.value`

### Satoshis (via Int64)

Per-block statistics and some internal fields use raw **satoshis** as `Int64`:

Examples: `BlockStats.avgfee`, `BlockStats.subsidy`, `BlockStats.totalfee`

The ``BlockStats`` doc comment notes: "All amount fields are in **satoshis** (raw `Int64`), not BTC."

## Fee Rates

Fee rates appear in two units across different RPCs:

| Unit | Where Used | Example Fields |
|------|-----------|----------------|
| **BTC/kvB** | Network and relay settings | `NetworkInfo.relayfee`, `MempoolInfo.mempoolminfee` |
| **sat/vB** | Block statistics | `BlockStats.avgfeerate`, `BlockStats.minfeerate` |

To convert between them: **1 sat/vB = 0.00001 BTC/kvB**.

The ``SmartFeeEstimate/feerate`` field is in BTC/kvB.

## Timestamps

### Unix Epoch Seconds (via UnixTimestamp)

Most time fields use ``UnixTimestamp``, which decodes from `Int64` and provides a `date` property:

```swift
let block: Block = ...
print(block.time.date) // Foundation Date
```

Examples: `Block.time`, `PeerInfo.lastsend`, `MempoolEntry.time`

### Special Cases

Not all integer time-like fields are ``UnixTimestamp``:

- **`getnettotals.timemillis`** -- Epoch **milliseconds**, uses plain `Int64`
- **`ban_duration`, `time_remaining`** -- **Durations** in seconds, not timestamps, uses plain `Int64`
- **`locktime`** -- Dual-use: block height when < 500,000,000, epoch seconds when >= 500,000,000. Uses plain `Int64`
- **Genesis `mediantime`** -- May be `0` as a sentinel for "not set"
