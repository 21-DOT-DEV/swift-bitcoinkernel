//
//  RPCError.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
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

    /// Creates an `RPCError`.
    ///
    /// - Parameters:
    ///   - code: The JSON-RPC error code (e.g., `-32601` for "Method not found").
    ///   - message: A short description of the error.
    ///   - data: Additional error data. Defaults to `nil`; almost never present in Bitcoin Core errors.
    public init(code: Int, message: String, data: String? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    public var description: String { "RPCError(\(code)): \(message)" }
    public var errorDescription: String? { description }
}
