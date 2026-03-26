//
//  bitcoind.h
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//

#ifndef BITCOIN_RPC_BRIDGE_H
#define BITCOIN_RPC_BRIDGE_H

int bitcoind_main(int argc, char* argv[]);

// Call BEFORE bitcoind_main(). appendCommand aborts if RPC is already running.
void bitcoin_rpc_register(void);

// After node is up, make ONE HTTP RPC call to "_bridge_init".
// That captures the NodeContext internally.
// All subsequent calls go direct — no HTTP.
// Returns heap-allocated JSON-RPC envelope. Caller must call bitcoin_free().
// Returns NULL if not yet bootstrapped.
char* bitcoin_rpc(const char* method, const char* params_json);

// Returns 1 if bootstrapped and ready for direct calls.
int bitcoin_rpc_ready(void);

void bitcoin_free(void* ptr);

// Call before raise(SIGTERM) to prevent use-after-free during teardown.
// Concurrent bitcoin_rpc() calls will return NULL instead of touching
// a half-destroyed NodeContext.
void bitcoin_rpc_reset(void);

#endif /* BITCOIN_RPC_BRIDGE_H */
