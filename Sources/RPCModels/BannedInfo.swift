//
//  BannedInfo.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Banned peer entry from `listbanned`.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct BannedInfo: Codable, Sendable, Equatable {
    public let address: String
    public let banCreated: Int64
    public let banExpires: Int64
    public let banDuration: Int64
    public let timeRemaining: Int64

    enum CodingKeys: String, CodingKey {
        case address
        case banCreated = "ban_created"
        case banExpires = "ban_expires"
        case banDuration = "ban_duration"
        case timeRemaining = "time_remaining"
    }
}
