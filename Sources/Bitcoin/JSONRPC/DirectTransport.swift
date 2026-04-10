//
//  DirectTransport.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import bitcoind

/// Sends JSON-RPC requests directly to the in-process Bitcoin Core dispatch
/// table via `bitcoin_rpc()`, bypassing HTTP entirely.
///
/// Conforms to ``RPCTransport`` only (not ``WalletCapableTransport``) — wallet
/// scoping is not supported over IPC. Throws ``RPCClientError/walletPathNotSupported``
/// if `path` is non-nil.
public struct DirectTransport: RPCTransport {

    public init() {}

    public func send(_ request: JSONRPCRequest, path: String?) async throws -> Data {
        if path != nil {
            throw RPCClientError.walletPathNotSupported
        }

        try Task.checkCancellation()

        let paramsData = try JSONEncoder().encode(request.params)
        let paramsJSON = String(data: paramsData, encoding: .utf8) ?? "[]"

        let resultPtr: UnsafeMutablePointer<CChar>? = request.method.withCString { method in
            paramsJSON.withCString { params in
                bitcoin_rpc(method, params)
            }
        }

        guard let ptr = resultPtr else {
            throw URLError(.cannotConnectToHost)
        }
        defer { bitcoin_free(UnsafeMutableRawPointer(ptr)) }

        return Data(bytes: ptr, count: strlen(ptr))
    }
}
