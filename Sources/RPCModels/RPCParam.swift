//
//  RPCParam.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
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
    case string(String)
    case int(Int)
    case int64(Int64)
    case double(Double)
    case bool(Bool)
    case null
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
