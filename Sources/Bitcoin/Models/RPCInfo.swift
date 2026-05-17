//
//  RPCInfo.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Details of the RPC server from `getrpcinfo`.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct RPCInfo: Codable, Sendable, Equatable {
    /// All currently active RPC commands.
    public let activeCommands: [ActiveCommand]

    /// The complete file path to the debug log.
    public let logpath: String

    enum CodingKeys: String, CodingKey {
        case activeCommands = "active_commands"
        case logpath
    }
}

/// Information about a currently active RPC command.
public struct ActiveCommand: Codable, Sendable, Equatable {
    /// The name of the RPC command.
    public let method: String

    /// The running time in microseconds.
    public let duration: Int64
}
