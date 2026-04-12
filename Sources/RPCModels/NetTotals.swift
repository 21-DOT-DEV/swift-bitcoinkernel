//
//  NetTotals.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Network traffic totals from `getnettotals`.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct NetTotals: Codable, Sendable, Equatable {
    /// Total bytes received.
    public let totalbytesrecv: Int64
    /// Total bytes sent.
    public let totalbytessent: Int64
    /// Current system UNIX epoch time in milliseconds.
    public let timemillis: Int64
    /// Upload target information.
    public let uploadtarget: UploadTarget
}

/// Upload target information from `getnettotals`.
public struct UploadTarget: Codable, Sendable, Equatable {
    /// Length of the measuring timeframe in seconds.
    public let timeframe: Int64
    /// Target in bytes.
    public let target: Int64
    /// Whether the target has been reached.
    public let targetReached: Bool
    /// Whether serving historical blocks.
    public let serveHistoricalBlocks: Bool
    /// Bytes left in current time cycle.
    public let bytesLeftInCycle: Int64
    /// Seconds left in current time cycle.
    public let timeLeftInCycle: Int64

    enum CodingKeys: String, CodingKey {
        case timeframe, target
        case targetReached = "target_reached"
        case serveHistoricalBlocks = "serve_historical_blocks"
        case bytesLeftInCycle = "bytes_left_in_cycle"
        case timeLeftInCycle = "time_left_in_cycle"
    }
}
