---
adr: 0001
title: Wallet support is RPC-only, with no separate Swift wallet library
status: Accepted
date: 2026-05-07
supersedes: []
superseded_by: null
---

# 0001 — Wallet support is RPC-only, with no separate Swift wallet library

## Context

The roadmap originally carried a dedicated wallet phase: a `BitcoinWalletSupport`
library target that would depend on a Swift BerkeleyDB wrapper and expose typed
wallet operations of its own. That framing treated the package as something a
user manages wallets with.

## Decision

Wallet functionality is reached through RPC only. The dedicated phase is absorbed
into the RPC client phase, and no separate wallet library product exists.
`BitcoinKernel` is a node layer that wallets and SDKs consume, not a wallet.

## Alternatives considered and rejected

A `BitcoinWalletSupport` product with a BerkeleyDB dependency and its own typed
wallet API. Rejected because it would add a runtime dependency and a second
public surface to maintain for behaviour Bitcoin Core already exposes over RPC,
and because it misstates what this package is for.

## Consequences

No BerkeleyDB dependency is taken. Wallet functionality is gated behind the
`wallet` package trait rather than a separate product, and wallet RPCs are routed
through transports conforming to `WalletCapableTransport`.
