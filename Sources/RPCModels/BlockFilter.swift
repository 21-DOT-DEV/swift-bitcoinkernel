//
//  BlockFilter.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Compact block filter data from `getblockfilter`.
public struct BlockFilter: Codable, Sendable, Equatable {
    /// The hex-encoded filter data.
    public let filter: String

    /// The hex-encoded filter header.
    public let header: String
}
