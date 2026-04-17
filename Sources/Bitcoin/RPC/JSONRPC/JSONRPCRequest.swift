//
//  JSONRPCRequest.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import RPCModels

/// Represents a JSON-RPC request to be sent to the Bitcoin node.
public struct JSONRPCRequest: Encodable, Sendable {
    /// The JSON-RPC version. Typically "1.0" for Bitcoin Core.
    let jsonrpc: String

    /// A unique identifier for the request.
    let id: String

    /// The name of the method to be invoked on the server.
    let method: String

    /// An array of parameters to pass to the method.
    let params: [RPCParam]

    /// Creates a new JSON-RPC request.
    ///
    /// - Parameters:
    ///   - jsonrpc: The JSON-RPC version. Defaults to "1.0".
    ///   - id: A unique identifier for the request. Defaults to "swift-bitcoin".
    ///   - method: The name of the method to be invoked on the server.
    ///   - params: An array of parameters to pass to the method. Defaults to an empty array.
    public init(jsonrpc: String = "1.0", id: String = "swift-bitcoin", method: String, params: [RPCParam] = []) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }
}
