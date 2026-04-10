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
    public let totalbytesrecv: Int64
    public let totalbytessent: Int64
    public let timemillis: Int64
    public let uploadtarget: UploadTarget
}

/// Upload target information.
public struct UploadTarget: Codable, Sendable, Equatable {
    public let timeframe: Int64
    public let target: Int64
    public let targetReached: Bool
    public let serveHistoricalBlocks: Bool
    public let bytesLeftInCycle: Int64
    public let timeLeftInCycle: Int64

    enum CodingKeys: String, CodingKey {
        case timeframe, target
        case targetReached = "target_reached"
        case serveHistoricalBlocks = "serve_historical_blocks"
        case bytesLeftInCycle = "bytes_left_in_cycle"
        case timeLeftInCycle = "time_left_in_cycle"
    }
}
