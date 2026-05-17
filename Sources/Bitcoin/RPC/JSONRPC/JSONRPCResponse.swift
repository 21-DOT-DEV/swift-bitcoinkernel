//
//  JSONRPCResponse.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//


/// A generic JSON-RPC response envelope.
///
/// `Result` is the expected type for this RPC's result field. The generic
/// decode path handles all RPCs without a type-switching `CommandResult` enum.
public struct JSONRPCResponse<Result: Decodable>: Decodable, Sendable
    where Result: Sendable {
    /// The decoded result, or `nil` if the server returned `null`.
    public let result: Result?

    /// A server error, or `nil` if the call succeeded.
    public let error: RPCError?

    /// The request ID this response corresponds to.
    public let id: String
}
