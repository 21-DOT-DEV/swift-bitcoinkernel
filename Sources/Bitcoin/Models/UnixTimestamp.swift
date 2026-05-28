//
//  UnixTimestamp.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Unix epoch seconds. Decodes/encodes as `Int64`.
///
/// Used for Bitcoin Core `NUM_TIME` fields: `time`, `blocktime`, `mediantime`,
/// `lastsend`, `lastrecv`, `conntime`, etc.
///
/// ```swift
/// let ts = UnixTimestamp(seconds: 1_700_000_000)
/// print(ts.date)        // 2023-11-14 22:13:20 +0000
/// print(ts.description) // ISO 8601 formatted string
/// ```
///
/// - Note: Some Core fields use 0 as a sentinel for "not set" (e.g., genesis
///   `mediantime`). Check `seconds == 0` at the call site where contextually
///   appropriate, or use `Optional<UnixTimestamp>` for fields that can be absent.
/// - Note: `locktime` is **not** a `UnixTimestamp` — it's dual-use (block height
///   when < 500,000,000, epoch seconds when ≥ 500,000,000).
/// - Note: `getnettotals.timemillis` is epoch **milliseconds** and uses `Int64`.
/// - Note: `ban_duration` / `time_remaining` are durations in seconds, not
///   epoch timestamps, and use `Int64`.
public struct UnixTimestamp: Codable, Sendable, Hashable, Comparable,
                             CustomStringConvertible, ExpressibleByIntegerLiteral {
    /// The timestamp in seconds since the Unix epoch.
    public let seconds: Int64

    /// The timestamp as a Foundation `Date`.
    public var date: Date { Date(timeIntervalSince1970: TimeInterval(seconds)) }

    /// Creates a `UnixTimestamp` from epoch seconds.
    public init(seconds: Int64) { self.seconds = seconds }

    /// Creates a `UnixTimestamp` from a Foundation `Date`.
    public init(_ date: Date) { self.seconds = Int64(date.timeIntervalSince1970) }

    // MARK: - ExpressibleByIntegerLiteral

    public init(integerLiteral value: Int64) { self.seconds = value }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        self.seconds = try decoder.singleValueContainer().decode(Int64.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(seconds)
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    // MARK: - Comparable

    public static func < (lhs: UnixTimestamp, rhs: UnixTimestamp) -> Bool {
        lhs.seconds < rhs.seconds
    }
}
