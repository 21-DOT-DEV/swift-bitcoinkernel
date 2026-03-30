//
//  RPCTransport.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Abstracts the raw data transport for JSON-RPC calls.
///
/// Conforming types handle sending a JSON-RPC request and returning the raw
/// response `Data`. Decoding is handled by `APIClient`, not the transport.
public protocol RPCTransport: Sendable {
    /// Send a JSON-RPC request and return the raw response data.
    ///
    /// - Parameter request: The JSON-RPC request to send.
    /// - Returns: The raw response data from the Bitcoin node.
    /// - Throws: A transport-level error (network failure, bridge unavailable, etc.).
    func send(request: JSONRPCRequest) async throws -> Data
}
