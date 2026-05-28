//
//  RPCParam.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// A parameter value for a JSON-RPC request.
///
/// RPC params are flat arrays of primitives. Complex params (e.g.,
/// `createrawtransaction` inputs/outputs) use dedicated `Encodable` structs
/// via `.encodable`. Not `Equatable` — `.encodable` carries an existential.
/// Test assertions should compare encoded `Data` output instead.
public enum RPCParam: Encodable, Sendable {
    /// A string parameter value.
    case string(String)
    /// An integer parameter value.
    case int(Int)
    /// A 64-bit integer parameter value (for values exceeding `Int` range).
    case int64(Int64)
    /// A floating-point parameter value.
    case double(Double)
    /// A boolean parameter value.
    case bool(Bool)
    /// An explicit JSON `null` parameter.
    case null
    /// A complex parameter encoded from a dedicated `Encodable` struct.
    case encodable(any Encodable & Sendable)

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v):    try c.encode(v)
        case .int64(let v):  try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v):   try c.encode(v)
        case .null:          try c.encodeNil()
        case .encodable(let v): try v.encode(to: encoder)
        }
    }
}
