//
//  BannedInfo.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Banned peer entry from `listbanned`.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct BannedInfo: Codable, Sendable, Equatable {
    /// The IP/Subnet of the banned node.
    public let address: String
    /// The UNIX epoch time the ban was created.
    public let banCreated: Int64
    /// The UNIX epoch time the ban expires.
    public let banExpires: Int64
    /// The ban duration, in seconds.
    public let banDuration: Int64
    /// The time remaining until the ban expires, in seconds.
    public let timeRemaining: Int64

    enum CodingKeys: String, CodingKey {
        case address
        case banCreated = "ban_created"
        case banExpires = "ban_expires"
        case banDuration = "ban_duration"
        case timeRemaining = "time_remaining"
    }
}
