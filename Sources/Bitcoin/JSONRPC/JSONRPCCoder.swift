//
//  JSONRPCCoder.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2024 Timechain Software Initiative 
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// A struct that provides encoding and decoding functionality for JSON-RPC requests and responses.
///
/// `JSONRPCCoder` encapsulates the `JSONEncoder` and `JSONDecoder` used for
/// serializing requests and deserializing responses in the JSON-RPC communication.
public struct JSONRPCCoder {
    /// The encoder used for serializing JSON-RPC request parameters.
    public var paramsEncoder: JSONEncoder
    
    /// The decoder used for deserializing JSON-RPC response results.
    public var resultDecoder: JSONDecoder

    /// Initializes a new `JSONRPCCoder` with default encoder and decoder.
    public init() {
        self.paramsEncoder = JSONEncoder()
        self.resultDecoder = JSONDecoder()
    }
}