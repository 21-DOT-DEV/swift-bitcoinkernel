//
//  AutoTransport.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import bitcoind

/// A transport that automatically selects between direct (in-process) and HTTP
/// on every call based on `bitcoin_rpc_ready()`.
///
/// When the direct bridge is bootstrapped, calls go through `DirectTransport`
/// with zero network overhead. Otherwise, calls fall back to `HTTPTransport`.
struct AutoTransport: RPCTransport {
    let http: any RPCTransport
    let direct: DirectTransport

    func send(_ request: JSONRPCRequest, path: String?) async throws -> Data {
        // Wallet RPCs (non-nil path) require HTTP — DirectTransport doesn't
        // support /wallet/<name> scoping.
        if path != nil {
            return try await http.send(request, path: path)
        }
        if bitcoin_rpc_ready() == 1 {
            return try await direct.send(request, path: nil)
        }
        return try await http.send(request, path: nil)
    }
}
