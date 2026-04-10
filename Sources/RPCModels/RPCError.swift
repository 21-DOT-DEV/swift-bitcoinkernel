//
//  RPCError.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// A server-originated JSON-RPC error from Bitcoin Core.
///
/// Thrown directly from the generic decode path when `response.error` is non-nil.
public struct RPCError: Error, Decodable, Sendable, Equatable, CustomStringConvertible, LocalizedError {
    /// The JSON-RPC error code (e.g., -32601 for "Method not found").
    public let code: Int

    /// A short description of the error.
    public let message: String

    /// Additional error data. Almost never present in Bitcoin Core errors.
    public let data: String?

    public init(code: Int, message: String, data: String? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    public var description: String { "RPCError(\(code)): \(message)" }
    public var errorDescription: String? { description }
}
