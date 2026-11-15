#ifndef SHA256_DISPATCH_PROBE_H
#define SHA256_DISPATCH_PROBE_H

#ifdef __cplusplus
extern "C" {
#endif

/// Returns Bitcoin Core's name for the SHA-256 implementation selected by
/// `SHA256AutoDetect()` on this build — e.g. "arm_shani(1way;2way)",
/// "sse4(1way)", or "standard". Deterministic, with one caveat: detection
/// rewrites the dispatcher's non-atomic function-pointer globals, so a
/// concurrent hash while any detect call is in flight is formally a C++ data
/// race. In practice it is benign on every supported target — writers are
/// idempotent (`kernel::Context` performs the same rewrite once via
/// `std::call_once`), every reachable value is a correct self-tested
/// implementation, and `SHA256D64` null-checks the multi-way pointers — but
/// it would trip TSan, so keep this off hot paths and out of concurrent
/// hashing. Returns "unknown" if detection throws.
const char* SHA256DispatchProbeSelectedImplementation(void);

#ifdef __cplusplus
}
#endif

#endif // SHA256_DISPATCH_PROBE_H
