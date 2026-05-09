//
//  RPCClientError.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Client-side RPC errors.
///
/// These represent errors in the client transport/decoding layer, not
/// server-originated errors (which are `RPCError` from `RPCModels`).
public enum RPCClientError: Error, Sendable, CustomStringConvertible, LocalizedError {
    /// The server returned `null` for an RPC that expects a non-null result.
    case unexpectedNullResult(method: String, responseData: Data)

    /// The response could not be decoded into the expected type.
    case decodingFailed(method: String, responseData: Data, underlying: Error)

    /// `submitBlock` returned a non-null rejection string.
    case blockRejected(reason: String)

    /// A wallet path was provided to a transport that doesn't support it.
    case walletPathNotSupported

    /// The RPC method name, if this error is associated with one.
    public var method: String? {
        switch self {
        case .unexpectedNullResult(let m, _), .decodingFailed(let m, _, _): return m
        case .blockRejected, .walletPathNotSupported: return nil
        }
    }

    public var description: String {
        switch self {
        case .unexpectedNullResult(let method, let data):
            let preview = String(data: data.prefix(1024), encoding: .utf8) ?? "<binary>"
            return "RPCClientError.unexpectedNullResult(method: \"\(method)\", data: \(preview))"
        case .decodingFailed(let method, let data, let underlying):
            let preview = String(data: data.prefix(1024), encoding: .utf8) ?? "<binary>"
            return "RPCClientError.decodingFailed(method: \"\(method)\", underlying: \(underlying), data: \(preview))"
        case .blockRejected(let reason):
            return "RPCClientError.blockRejected(reason: \"\(reason)\")"
        case .walletPathNotSupported:
            return "RPCClientError.walletPathNotSupported"
        }
    }

    public var errorDescription: String? { description }
}
