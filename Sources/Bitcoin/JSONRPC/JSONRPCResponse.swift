//
//  JSONRPCResponse.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2024 Timechain Software Initiative 
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Represents a JSON-RPC response from the Bitcoin node.
public struct JSONRPCResponse: Codable, Sendable {
    /// The result of the JSON-RPC call.
    public let result: CommandResult
    
    /// An error object if the call was unsuccessful, or `nil` if successful.
    public let error: JSONRPCError?
    
    /// The ID of the request this response corresponds to.
    public let id: String

    /// Creates a new `JSONRPCResponse` instance from a decoder.
    ///
    /// - Parameter decoder: The decoder to read data from.
    /// - Throws: An error if decoding fails.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        result = try container.decode(CommandResult.self, forKey: .result)
        error = try container.decodeIfPresent(JSONRPCError.self, forKey: .error)
        id = try container.decode(String.self, forKey: .id)
    }

    /// Encodes the `JSONRPCResponse` instance to an encoder.
    ///
    /// - Parameter encoder: The encoder to write data to.
    /// - Throws: An error if encoding fails.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(result, forKey: .result)
        try container.encodeIfPresent(error, forKey: .error)
        try container.encode(id, forKey: .id)
    }

    /// Coding keys for `JSONRPCResponse`.
    private enum CodingKeys: String, CodingKey {
        case result, error, id
    }
}

/// Represents the possible result types of a JSON-RPC command.
public enum CommandResult: Codable, Sendable {
    /// Represents an integer result.
    case integer(Int)
    
    /// Represents a `BlockchainInfo` result.
    case blockchainInfo(BlockchainInfo)
    
    /// Represents a `BlockWithTransactions` result.
    case blockWithTransactions(BlockWithTransactions)
    
    /// Represents a `Block` result.
    case block(Block)
    
    /// Represents a string result.
    case string(String)
    
    /// Represents a null result.
    case null

    /// Creates a new `CommandResult` instance from a decoder.
    ///
    /// - Parameter decoder: The decoder to read data from.
    /// - Throws: An error if decoding fails or if the type doesn't match any case.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Int.self) {
            self = .integer(x)
        } else if let x = try? container.decode(String.self) {
            self = .string(x)
        } else if let x = try? container.decode(BlockchainInfo.self) {
            self = .blockchainInfo(x)
        } else if let x = try? container.decode(BlockWithTransactions.self) {
            self = .blockWithTransactions(x)
        } else if let x = try? container.decode(Block.self) {
            self = .block(x)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.typeMismatch(
                CommandResult.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for CommandResult")
            )
        }
    }

    /// Encodes the `CommandResult` instance to an encoder.
    ///
    /// - Parameter encoder: The encoder to write data to.
    /// - Throws: An error if encoding fails.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .integer(let x):
            try container.encode(x)
        case .blockchainInfo(let x):
            try container.encode(x)
        case .blockWithTransactions(let x):
            try container.encode(x)
        case .block(let x):
            try container.encode(x)
        case .string(let x):
            try container.encode(x)
        case .null:
            try container.encodeNil()
        }
    }
}
