//
//  APIClient.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

// Assuming JSONRPCRequest, JSONRPCResponse, JSONRPCService, and related types are already defined.

public class APIClient {
    private let rpcService: JSONRPCService

    public init(service: JSONRPCService = JSONRPCService(url: URL(string: "http://111:222@127.0.0.1:8332")!)) {
        self.rpcService = service
    }

    // Example RPC method
    public func command<T: Codable>(_ command: Commands) async throws -> T {
        let request = JSONRPCRequest(jsonrpc: "1.0", method: command.rawValue, params: [], id: 1)
        return try await rpcService.send(request: request)
    }
}
