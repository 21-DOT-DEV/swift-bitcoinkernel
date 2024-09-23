//
//  JSONRPCRequest.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2024 Timechain Software Initiative 
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Represents a JSON-RPC request to be sent to the Bitcoin node.
public struct JSONRPCRequest: Codable {
    /// The JSON-RPC version. Typically "1.0" for Bitcoin Core.
    let jsonrpc: String
    
    /// A unique identifier for the request.
    let id: String
    
    /// The name of the method to be invoked on the server.
    let method: String
    
    /// An array of parameters to pass to the method.
    let params: [AnyCodable]

    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, method, params
    }

    /// Creates a new JSON-RPC request.
    ///
    /// - Parameters:
    ///   - jsonrpc: The JSON-RPC version. Defaults to "1.0".
    ///   - id: A unique identifier for the request. Defaults to "swift-bitcoin".
    ///   - method: The name of the method to be invoked on the server.
    ///   - params: An array of parameters to pass to the method. Defaults to an empty array.
    public init(jsonrpc: String = "1.0", id: String = "swift-bitcoin", method: String, params: [Any] = []) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params.map { AnyCodable($0) }
    }
}

// AnyCodable wrapper
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictionaryValue = try? container.decode([String: AnyCodable].self) {
            value = dictionaryValue.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map { AnyCodable($0) })
        case let dictionaryValue as [String: Any]:
            try container.encode(dictionaryValue.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "AnyCodable value cannot be encoded"))
        }
    }
}
