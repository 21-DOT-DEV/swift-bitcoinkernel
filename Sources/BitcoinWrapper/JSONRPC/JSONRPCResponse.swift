//
//  JSONRPCResponse.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

public struct JSONRPCResponse<T: Codable>: Codable {
    let result: T?
    let error: JSONRPCError?
    let id: Int
}
