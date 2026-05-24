# bridge/

Swift ↔ bitcoind interop code. **Everything in this directory is original
to `swift-bitcoinkernel`.** Every other file under `Sources/bitcoind/src/` is
vendored from upstream Bitcoin Core (`Vendor/bitcoin/src/`) and MUST NOT
be edited directly — use a file here instead.

This directory exists because `swift-bitcoinkernel` embeds `bitcoind_main()`
in-process and calls it multiple times during a single app session (each
node start/stop cycle). The upstream codebase assumes one-process-per-run:
various globals are set during shutdown and never reset, because the
process exits right after. We paper over those assumptions here.

## Ground rules

1. **No edits to vendored files.** Every workaround must live in this
   directory so the `Vendor/bitcoin` subtree can be re-synced cleanly.
2. **Header declarations go in `Sources/bitcoind/include/bitcoind.h`.**
   That's the single exported header in the `bitcoind` module map, so
   any symbol Swift needs to call must be declared there.
3. **One shim = one file.** Keeps attribution and intent explicit.
4. **Every file opens with a block comment** explaining the upstream
   problem it solves and pointing at the relevant upstream line.
5. **Call every shim from `Sources/Bitcoin/Daemon.swift`,** on the
   `Thread.detachNewThread` block, before `bitcoind_main()`. That is
   the single integration point for per-run setup.

## Contents

### `bitcoin_rpc.cpp`

Direct in-process RPC bridge. Registers a hidden `_bridge_init` RPC
before `bitcoind_main()` starts the RPC server; one HTTP call after
startup captures the `NodeContext`; all subsequent RPCs dispatch
through `tableRPC.execute()` without HTTP. Also exposes `bitcoin_free`
for releasing heap strings returned by `bitcoin_rpc()`.

### `bitcoin_socks_reset.cpp`

Resets `g_socks5_interrupt` before every `bitcoind_main()` call.
Upstream sets this global during shutdown (at `net.cpp:3595`) to abort
in-flight SOCKS5 handshakes, but never clears it. On the second
in-process run every SOCKS5 `InterruptibleRecv()` trips the check at
`netbase.cpp:343` and fails with
"InterruptibleRecv() timeout or other failure", breaking all Tor
outbound connections. Clearing the flag per run restores correct
behaviour.

## Adding a new shim

1. Create `bitcoin_<subsystem>_<verb>.cpp` in this directory. Include
   only the upstream headers you actually need.
2. Declare the entry point in
   `Sources/bitcoind/include/bitcoind.h` with a comment describing
   when Swift must call it.
3. Call it from the `Thread.detachNewThread` block in
   `Sources/Bitcoin/Daemon.swift`, alongside `bitcoin_socks_reset()`
   and `bitcoin_rpc_register()`.
4. Document the upstream symptom and the exact upstream line(s) in the
   file's top comment, and add a one-paragraph entry under
   **Contents** above.
