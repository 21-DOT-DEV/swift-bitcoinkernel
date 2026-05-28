//
//  NodeDiagnostics.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2022-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Darwin
import Foundation
import os.log

/// Process-level resource diagnostics for troubleshooting Tor + bitcoind
/// lifecycle transitions.
///
/// Emits one compact log line per call so snapshots across transitions are
/// trivially diffable. Intended for debugging resource-exhaustion scenarios
/// (FD leaks, thread leaks, TIME_WAIT accumulation) that correlate with
/// SOCKS5 handshake stalls on in-process Tor restarts.
///
/// Example output:
/// ```
/// DIAG [after-tor-start-1] fd=42 threads=8 rlim_cur=10240 rlim_max=10240
/// DIAG [after-node-start-1] fd=86 threads=31 rlim_cur=10240 rlim_max=10240
/// DIAG [after-node-stop-1] fd=54 threads=11 rlim_cur=10240 rlim_max=10240
/// ```
///
/// ## Interpreting the output
/// - **Monotonically-rising `fd=`**: file-descriptor leak.
/// - **`fd=` approaches `rlim_cur`**: process near FD exhaustion.
/// - **Rising `threads=` across stop/start cycles**: thread leak (likely Tor or bitcoind).
/// - **Low `rlim_cur`** on iOS Simulator (~1024): kernel-imposed cap.
enum NodeDiagnostics {

    #if DEBUG
    private static let logger = Logger(subsystem: "dev.21.Bitcoin", category: "Diagnostics")
    #endif

    /// Emit one snapshot line tagged with `tag`.
    ///
    /// Tags should include a lifecycle phase AND a run counter so transitions
    /// are diffable (e.g. `"before-node-start-2"`, `"after-tor-stop-1"`).
    ///
    /// Release builds have an empty body — the ~10k `fcntl` syscalls per call
    /// plus synchronous main-actor execution are only worthwhile when actively
    /// debugging resource-leak scenarios.
    ///
    /// - Parameter tag: A short, stable identifier for the call site.
    static func snapshot(_ tag: String) {
    #if DEBUG
        let rlim = rlimitNOFILE()
        let fdCount = openFileDescriptorCount(upperBound: rlim.soft)
        let threads = threadCount()

        logger.info(
            """
            DIAG [\(tag, privacy: .public)] \
            fd=\(fdCount, privacy: .public) \
            threads=\(threads, privacy: .public) \
            rlim_cur=\(rlim.soft, privacy: .public) \
            rlim_max=\(rlim.hard, privacy: .public)
            """
        )
    #endif
    }

    // MARK: - Primitives

    #if DEBUG
    /// Read the current RLIMIT_NOFILE soft (`rlim_cur`) and hard (`rlim_max`) limits.
    ///
    /// Caps returned values at `Int.max / 2` so callers can safely use them
    /// as loop bounds without overflow when the kernel reports `RLIM_INFINITY`.
    private static func rlimitNOFILE() -> (soft: Int, hard: Int) {
        var lim = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &lim) == 0 else { return (-1, -1) }
        let cap = rlim_t(Int.max / 2)
        let soft = Int(min(lim.rlim_cur, cap))
        let hard = Int(min(lim.rlim_max, cap))
        return (soft, hard)
    }

    /// Count live file descriptors in range `0 ..< min(upperBound, 16384)`.
    ///
    /// Uses `fcntl(fd, F_GETFD)` which returns `-1` for closed FDs (without
    /// errno side-effects that matter to us). 16 384 is a defensive cap to
    /// bound scan time if `rlim_cur` is `RLIM_INFINITY` or unexpectedly huge.
    private static func openFileDescriptorCount(upperBound: Int) -> Int {
        let scanLimit = min(upperBound > 0 ? upperBound : 1024, 16_384)
        var count = 0
        for fd in 0..<Int32(scanLimit) {
            if fcntl(fd, F_GETFD) != -1 {
                count += 1
            }
        }
        return count
    }

    /// Current live thread count of the calling process (Darwin-only).
    private static func threadCount() -> Int {
        var threadList: thread_act_array_t?
        var threadCountMach: mach_msg_type_number_t = 0
        let kr = task_threads(mach_task_self_, &threadList, &threadCountMach)
        guard kr == KERN_SUCCESS, let threadList else { return -1 }
        // Release the thread-port rights Mach handed us.
        for i in 0..<Int(threadCountMach) {
            mach_port_deallocate(mach_task_self_, threadList[i])
        }
        vm_deallocate(
            mach_task_self_,
            vm_address_t(UInt(bitPattern: threadList)),
            vm_size_t(Int(threadCountMach) * MemoryLayout<thread_t>.size)
        )
        return Int(threadCountMach)
    }
    #endif

    // MARK: - SOCKS5 active probe

    #if DEBUG
    /// Outcome of a single SOCKS5 method-selection handshake probe.
    ///
    /// These classifications distinguish the observable failure modes that
    /// matter for diagnosing whether Tor's SOCKS listener is alive, hung,
    /// or silently dropping connections.
    enum SocksProbeOutcome: CustomStringConvertible {
        /// Tor responded with a valid 2-byte method-selection reply.
        case ok(version: UInt8, method: UInt8)
        /// `socket()` / `connect()` failed at the OS layer.
        case tcpFail(errno: Int32)
        /// `send()` failed (partial write or error) before the request left.
        case sendFail(errno: Int32, bytesSent: Int)
        /// `recv()` returned 0 — peer closed the connection after our request.
        /// This is the "Tor accepted the TCP but silently dropped" case.
        case disconnected
        /// `recv()` timed out (EAGAIN/EWOULDBLOCK after `SO_RCVTIMEO`).
        /// Tor accepted the TCP but never wrote a byte back.
        case timeout
        /// `recv()` returned a partial or nonsensical response.
        case badResponse(bytes: [UInt8])

        var description: String {
            switch self {
            case .ok(let v, let m):
                return "ok(ver=\(v),method=\(m))"
            case .tcpFail(let e):
                return "tcp_fail(errno=\(e))"
            case .sendFail(let e, let n):
                return "send_fail(errno=\(e),sent=\(n))"
            case .disconnected:
                return "disconnected"
            case .timeout:
                return "timeout"
            case .badResponse(let bytes):
                return "bad_response(\(bytes.map { String(format: "%02x", $0) }.joined()))"
            }
        }
    }

    #endif

    /// Actively probe a SOCKS5 listener and log the outcome tagged for diffing.
    ///
    /// Performs a complete SOCKS5 method-selection handshake against
    /// `127.0.0.1:port`: connect → send `[0x05, 0x01, 0x00]` (version 5,
    /// 1 method advertised, NO_AUTH) → receive 2 bytes `[version, method]`.
    ///
    /// Release builds have an empty body — the synchronous socket handshake
    /// and 2 s timeout are only useful when actively debugging Tor listener
    /// behavior.
    ///
    /// - Parameters:
    ///   - port: The Tor SOCKS port (pass `socksEndpoint?.port` from the Tor view model).
    ///   - tag: Stable identifier for the call site (e.g. `"after-node-stop-1"`).
    static func probeSocks5(port: UInt16?, tag: String) {
    #if DEBUG
        guard let port else {
            logger.info("DIAG [probe@\(tag, privacy: .public)] socks5=skipped(no_port)")
            return
        }
        let outcome = performSocks5Probe(port: port, timeoutSeconds: 2)
        logger.info(
            "DIAG [probe@\(tag, privacy: .public)] socks5=\(outcome.description, privacy: .public) port=\(port, privacy: .public)"
        )
    #endif
    }

    #if DEBUG
    /// Raw SOCKS5 probe implementation. All errors are reported as structured
    /// `SocksProbeOutcome` values; the function never throws.
    private static func performSocks5Probe(port: UInt16, timeoutSeconds: Int) -> SocksProbeOutcome {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return .tcpFail(errno: errno) }
        defer { _ = Darwin.close(fd) }

        // Bound both send and receive so a hung listener can't stall us.
        var tv = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let connectResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectResult == 0 else { return .tcpFail(errno: errno) }

        // SOCKS5 method-selection request: version=5, nmethods=1, NO_AUTH(0x00).
        let request: [UInt8] = [0x05, 0x01, 0x00]
        let sent = request.withUnsafeBufferPointer { buf in
            send(fd, buf.baseAddress, buf.count, 0)
        }
        guard sent == 3 else { return .sendFail(errno: errno, bytesSent: sent) }

        // Expected reply: 2 bytes [version, selected_method]. Valid Tor reply
        // is either 0x05 0x00 (NO_AUTH accepted) or 0x05 0xFF (no acceptable).
        var response: [UInt8] = [0, 0]
        let received = response.withUnsafeMutableBufferPointer { buf in
            recv(fd, buf.baseAddress, 2, 0)
        }
        if received == 0 {
            return .disconnected
        }
        if received < 0 {
            if errno == EAGAIN || errno == EWOULDBLOCK {
                return .timeout
            }
            // Fold other recv errors into disconnected — they all indicate
            // Tor didn't give us a SOCKS reply.
            return .disconnected
        }
        if received == 2 {
            return .ok(version: response[0], method: response[1])
        }
        return .badResponse(bytes: Array(response.prefix(Int(received))))
    }
    #endif
}
