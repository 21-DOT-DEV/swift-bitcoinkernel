// bitcoin_socks_reset.cpp
// Reset the sticky SOCKS5 interrupt flag for in-process daemon restarts.
//
// `g_socks5_interrupt` is a file-scope global in `netbase.cpp` (line 41)
// that gets *set* during shutdown via `CConnman::Interrupt()` at
// `net.cpp:3595`. Upstream Bitcoin Core never resets it — in the normal
// process model the process exits right after shutdown, so the flag's
// lifetime ends with the process.
//
// In this project's in-process model `bitcoind_main()` is called
// multiple times in the same process. On the second and later
// invocations the flag is still set from the previous shutdown, and
// every SOCKS5 handshake started by bitcoind's networking threads
// trips this check inside `InterruptibleRecv()` at `netbase.cpp:343`:
//
//     if (g_socks5_interrupt) {
//         return IntrRecvError::Interrupted;
//     }
//
// which is surfaced to the log as:
//
//     Socks5() connect to X:Y failed:
//     InterruptibleRecv() timeout or other failure
//
// The only correct fix is to clear the flag before we re-enter
// `bitcoind_main()`. This keeps all upstream source files untouched.
//
// Same class of in-process-restart bug as the `noui` signal handlers.

#include <netbase.h>

void bitcoin_socks_reset(void) {
    g_socks5_interrupt.reset();
}
