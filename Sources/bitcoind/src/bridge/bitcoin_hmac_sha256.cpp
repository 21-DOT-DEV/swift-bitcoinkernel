// bitcoin_hmac_sha256.cpp
// Expose Bitcoin Core's HMAC-SHA256 (CHMAC_SHA256, vendored at
// crypto/hmac_sha256.h) to Swift so RPCAuth can derive the `-rpcauth=`
// password HMAC natively, instead of shelling out to
// share/rpcauth/rpcauth.py.
//
// Unlike the other shims in this directory, this is not a per-run lifecycle
// reset that papers over an in-process-restart assumption: it is a pure
// compute helper. Swift calls it from RPCAuth, not from the bitcoind_main()
// thread. Reusing the exact CHMAC_SHA256 that bitcoind itself uses for
// rpcauth guarantees the generated credential matches what the daemon expects.

#include <crypto/hmac_sha256.h>

void bitcoin_hmac_sha256(const unsigned char* key, size_t keylen,
                         const unsigned char* msg, size_t msglen,
                         unsigned char* out) {
    CHMAC_SHA256(key, keylen).Write(msg, msglen).Finalize(out);
}
