//
//  ZMQNotification.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// ZMQ notification endpoint from `getzmqnotifications` (v17+).
///
/// - Note: Targets Bitcoin Core v31.x.
public struct ZMQNotification: Codable, Sendable, Equatable {
    /// Notification type (e.g., "pubhashblock", "pubhashtx", "pubrawblock", "pubrawtx").
    public let type: String

    /// ZMQ endpoint address.
    public let address: String

    /// High water mark for the notification.
    public let hwm: Int
}
