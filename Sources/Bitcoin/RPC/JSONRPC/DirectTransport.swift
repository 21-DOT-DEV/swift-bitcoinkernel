//
//  DirectTransport.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

@preconcurrency import Dispatch
import Foundation
import Synchronization
import bitcoind

/// Lock-free flag for exactly-once continuation resumption.
///
/// Wraps `Atomic<Bool>` in a `Sendable` class so it can be captured by
/// GCD closures. Compare-and-swap ensures only one of the timeout or
/// completion path resumes the continuation.
private final class OnceFlag: Sendable {
    private let _flag = Atomic(false)

    /// Claims the flag. Returns `true` if this is the first caller.
    func claim() -> Bool {
        _flag.compareExchange(
            expected: false,
            desired: true,
            ordering: .acquiringAndReleasing
        ).exchanged
    }
}

/// Sends JSON-RPC requests directly to the in-process Bitcoin Core dispatch
/// table via `bitcoin_rpc()`, bypassing HTTP entirely.
///
/// Conforms to ``RPCTransport`` only (not ``WalletCapableTransport``) — wallet
/// scoping is not supported over IPC. Throws ``RPCClientError/walletPathNotSupported``
/// if `path` is non-nil.
public struct DirectTransport: RPCTransport {

    /// Timeout for the blocking `bitcoin_rpc()` call. Matches Bitcoin Core's
    /// default `-rpcservertimeout` (30 s). After this interval the continuation
    /// resumes with `URLError(.timedOut)`; the GCD thread keeps running (a
    /// synchronous C call cannot be cancelled) and frees its memory on return.
    public var timeout: TimeInterval

    /// Creates a direct transport that calls `bitcoin_rpc()` in-process.
    ///
    /// - Parameter timeout: Maximum seconds to wait for the blocking `bitcoin_rpc()` call before resuming with `URLError(.timedOut)`. Defaults to `30`, matching Bitcoin Core's `-rpcservertimeout`.
    public init(timeout: TimeInterval = 30) {
        self.timeout = timeout
    }

    /// Sends a JSON-RPC request directly to the in-process `bitcoin_rpc()` C bridge.
    ///
    /// `bitcoin_rpc()` is synchronous and may block indefinitely waiting for
    /// internal locks (e.g. `cs_main` during initial block download). To honor
    /// Swift concurrency's forward-progress contract, the blocking call is
    /// dispatched to a GCD thread and bridged back via a checked continuation.
    ///
    /// If the call does not complete within ``timeout`` seconds, the
    /// continuation resumes with a timeout error. The underlying C call
    /// continues on its GCD thread — its memory is freed when it returns.
    ///
    /// Wallet-scoped calls (non-nil `path`) are not supported over the direct
    /// transport and throw ``RPCClientError/walletPathNotSupported``.
    public func send(_ request: JSONRPCRequest, path: String?) async throws -> Data {
        if path != nil {
            throw RPCClientError.walletPathNotSupported
        }

        try Task.checkCancellation()

        let paramsData = try JSONEncoder().encode(request.params)
        let paramsJSON = String(data: paramsData, encoding: .utf8) ?? "[]"
        let method = request.method
        let deadline = timeout

        // bitcoin_rpc() is a synchronous C call that may block indefinitely
        // waiting for internal locks (e.g. cs_main during initial block
        // download). Dispatch to GCD so the cooperative pool stays free.
        // Ref: WWDC 2022 "Visualize and optimize Swift concurrency"
        //
        // A timeout guard ensures the continuation resumes within `deadline`
        // seconds. OnceFlag (Atomic<Bool>) guarantees exactly-once resumption.
        return try await withCheckedThrowingContinuation { continuation in
            let resumed = OnceFlag()

            // — Timeout guard (cancellable) —
            let timeoutWork = DispatchWorkItem {
                if resumed.claim() {
                    continuation.resume(throwing: URLError(.timedOut))
                }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + deadline,
                execute: timeoutWork
            )

            // — Blocking RPC call —
            DispatchQueue.global(qos: .userInitiated).async {
                let resultPtr: UnsafeMutablePointer<CChar>? = method.withCString { m in
                    paramsJSON.withCString { p in
                        bitcoin_rpc(m, p)
                    }
                }

                guard resumed.claim() else {
                    // Timed out — just free the C memory.
                    if let ptr = resultPtr { bitcoin_free(UnsafeMutableRawPointer(ptr)) }
                    return
                }

                // RPC won the race — cancel the dangling timeout timer.
                timeoutWork.cancel()

                guard let ptr = resultPtr else {
                    continuation.resume(throwing: URLError(.cannotConnectToHost))
                    return
                }

                let data = Data(bytes: ptr, count: strlen(ptr))
                bitcoin_free(UnsafeMutableRawPointer(ptr))
                continuation.resume(returning: data)
            }
        }
    }
}
