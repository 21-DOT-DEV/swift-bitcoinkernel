//
//  BlockFilter.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
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
