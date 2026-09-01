---
adr: 0002
title: Peer-to-peer networking replaces the remote-node HTTP client model
status: Accepted
date: 2026-05-07
supersedes: []
superseded_by: null
---

# 0002 — Peer-to-peer networking replaces the remote-node HTTP client model

## Context

The roadmap originally planned a network-based `BitcoinClient` that would connect
to somebody else's Bitcoin Core node over HTTP JSON-RPC. By the time that phase
came up, HTTP transport had already shipped in the RPC client phase as
`HTTPTransport`, which covered the connect-to-a-remote-node case on its own.

## Decision

The remote-node connection model is replaced by talking to the Bitcoin network
directly. The single planned phase is split into three: peer-to-peer networking,
compact block filters, and advanced peer-to-peer work.

## Alternatives considered and rejected

Keeping a separate network client product layered on HTTP JSON-RPC. Rejected as
duplicate surface: `HTTPTransport` already does it, and a client that depends on
a remote node contradicts the goal of an embedded node.

## Consequences

There is no separate network-client product. Three roadmap phases replace one,
and the two phase files describing the abandoned plan were removed once this
record captured why.
