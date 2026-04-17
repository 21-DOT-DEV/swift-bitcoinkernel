// bitcoin_rpc.cpp
// Direct RPC bridge — no modifications to existing Bitcoin Core files.
//
// Flow:
//   1. Call bitcoin_rpc_register() BEFORE bitcoind_main().
//      Registers the hidden "_bridge_init" RPC in tableRPC while the
//      RPC server is not yet running (appendCommand aborts otherwise).
//   2. After the node is up, make ONE HTTP call to "_bridge_init".
//      That call captures the NodeContext pointer from request.context.
//   3. All subsequent RPCs call bitcoin_rpc() — direct dispatch, no HTTP.
//   4. Before raise(SIGTERM), call bitcoin_rpc_reset() to close the gate.

#include <rpc/server.h>
#include <rpc/server_util.h>
#include <rpc/request.h>
#include <node/context.h>
#include <univalue.h>

#include <string>
#include <cstring>
#include <atomic>

static std::atomic<node::NodeContext*> g_node_ctx{nullptr};
static std::atomic<bool> g_ready{false};

static char* to_heap(const std::string& s) {
    char* p = static_cast<char*>(malloc(s.size() + 1));
    if (p) memcpy(p, s.c_str(), s.size() + 1);
    return p;
}

// Hidden RPC handler. Called once via HTTP to capture NodeContext.
static RPCHelpMan bridge_init_rpc() {
    return RPCHelpMan{
        "_bridge_init",
        "Internal: captures node context for direct RPC bridge. Do not call manually.\n",
        {},
        RPCResults{RPCResult{RPCResult::Type::STR, "", "status"}},
        RPCExamples{""},
        [](const RPCHelpMan&, const JSONRPCRequest& request) -> UniValue {
            if (!g_ready.load()) {
                g_node_ctx.store(&EnsureAnyNodeContext(request.context));
                g_ready.store(true);
            }
            return UniValue{"ok"};
        },
    };
}

// Register the "_bridge_init" command. Must be called before bitcoind_main()
// because appendCommand has CHECK_NONFATAL(!IsRPCRunning()).
// Idempotent: the static CRPCCommand and tableRPC entry persist across
// in-process restarts (tableRPC is a global, never destroyed), so
// registration only needs to happen once per process lifetime.
void bitcoin_rpc_register(void) {
    static bool registered = false;
    if (registered) return;
    registered = true;
    static CRPCCommand cmd{"hidden", &bridge_init_rpc};
    tableRPC.appendCommand(cmd.name, &cmd);
}

int bitcoin_rpc_ready(void) {
    return g_ready.load() ? 1 : 0;
}

// Returns a heap-allocated JSON-RPC envelope string (identical format to HTTP):
//   Success: {"result": <value>, "error": null, "id": 1}
//   Failure: {"result": null, "error": {...}, "id": 1}
// Returns NULL if the bridge is not yet bootstrapped.
// Caller must pass the result to bitcoin_free().
char* bitcoin_rpc(const char* method, const char* params_json) {
    if (!method || !g_ready.load()) return nullptr;

    // Load into a local so a concurrent bitcoin_rpc_reset() cannot null
    // the pointer between our check and use (TOCTOU).
    node::NodeContext* ctx = g_node_ctx.load();
    if (!ctx) return nullptr;

    try {
        UniValue params{UniValue::VARR};
        if (params_json && *params_json) params.read(params_json);
        if (!params.isArray()) {
            UniValue arr{UniValue::VARR};
            arr.push_back(params);
            params = arr;
        }

        JSONRPCRequest req;
        req.strMethod = method;
        req.params    = params;
        req.context   = ctx;

        UniValue result = tableRPC.execute(req);

        UniValue envelope{UniValue::VOBJ};
        envelope.pushKV("result", result);
        envelope.pushKV("error", UniValue{});
        envelope.pushKV("id", UniValue{std::string{"1"}});
        return to_heap(envelope.write());

    } catch (const UniValue& e) {
        UniValue envelope{UniValue::VOBJ};
        envelope.pushKV("result", UniValue{});
        envelope.pushKV("error", e);
        envelope.pushKV("id", UniValue{std::string{"1"}});
        return to_heap(envelope.write());

    } catch (const std::exception& e) {
        UniValue err{UniValue::VOBJ};
        err.pushKV("code",    -32603);
        err.pushKV("message", e.what());
        UniValue envelope{UniValue::VOBJ};
        envelope.pushKV("result", UniValue{});
        envelope.pushKV("error", err);
        envelope.pushKV("id", UniValue{std::string{"1"}});
        return to_heap(envelope.write());
    }
}

// Clear bridge state so concurrent bitcoin_rpc() calls return NULL immediately
// instead of touching a half-destroyed NodeContext. Must be called from Swift
// BEFORE triggering the "stop" RPC to close the gate ahead of teardown.
void bitcoin_rpc_reset(void) {
    g_ready.store(false);
    g_node_ctx.store(nullptr);
}

void bitcoin_free(void* ptr) {
    free(ptr);
}
