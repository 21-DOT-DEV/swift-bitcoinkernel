//
//  JSONRPCError.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2024 Timechain Software Initiative 
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Represents an error returned in a JSON-RPC response.
public struct JSONRPCError: Codable, Sendable {
    /// The error code.
    public let code: Int
    
    /// A short description of the error.
    public let message: String
}
