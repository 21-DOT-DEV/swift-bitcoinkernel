//
//  RPCTransport.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Abstracts the raw data transport for JSON-RPC calls.
///
/// Conforming types handle sending a JSON-RPC request and returning the raw
/// response `Data`. Decoding is handled by `RPCClient`, not the transport.
///
/// - Important: `send(_:path:)` is a **required** method with no default
///   implementation. All conformances must handle the `path` parameter
///   explicitly — a default impl would let third-party conformances silently
///   drop wallet scoping.
public protocol RPCTransport: Sendable {
    /// Send a JSON-RPC request and return the raw response data.
    ///
    /// - Parameters:
    ///   - request: The JSON-RPC request to send.
    ///   - path: An optional path suffix (e.g., `/wallet/<name>` for wallet RPCs).
    /// - Returns: The raw response data from the Bitcoin node.
    /// - Throws: A transport-level error (network failure, bridge unavailable, etc.).
    func send(_ request: JSONRPCRequest, path: String?) async throws -> Data
}

/// Transports that support wallet path scoping.
///
/// The wallet follow-up plan constrains `WalletClient.init` to this protocol,
/// making `WalletClient(transport: directTransport)` a compile error.
public protocol WalletCapableTransport: RPCTransport {}
