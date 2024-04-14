//
//  JSONRPCRequest.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

public struct JSONRPCRequest: Codable {
    let jsonrpc: String
    let method: String
    let params: [String]
    let id: Int
}
