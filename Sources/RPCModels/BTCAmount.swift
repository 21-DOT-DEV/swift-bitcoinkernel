//
//  BTCAmount.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Single Bitcoin amount type. Stores satoshis, decodes/encodes BTC decimal.
///
/// Fields in sat-denominated Core JSON use plain `Int64` instead.
/// Negative amounts are valid and expected (e.g., `fee` in wallet transactions).
///
/// - Note: Targets Bitcoin Core v31.x.
public struct BTCAmount: Codable, Sendable, Hashable, Comparable, AdditiveArithmetic, CustomStringConvertible {
    /// The amount in satoshis. Source of truth. Signed — negative amounts valid.
    public let satoshis: Int64

    /// Number of satoshis per BTC.
    public static let satoshisPerBTC: Int64 = 100_000_000

    /// The amount as a BTC `Decimal`. Computed, not stored.
    public var btc: Decimal { Decimal(satoshis) / Decimal(Self.satoshisPerBTC) }

    /// Creates a `BTCAmount` from a satoshi value.
    public init(satoshis: Int64) { self.satoshis = satoshis }

    /// Creates a `BTCAmount` from a BTC `Decimal` value.
    ///
    /// - Note: Double literals (e.g., `BTCAmount(btc: 2.09999999)`) go through
    ///   Double → Decimal conversion which may lose precision BEFORE rounding.
    ///   For exact values, use `BTCAmount(btc: Decimal(string: "2.09999999")!)`.
    public init(btc: Decimal) {
        let handler = NSDecimalNumberHandler(
            roundingMode: .plain, scale: 0,
            raiseOnExactness: false, raiseOnOverflow: true,
            raiseOnUnderflow: false, raiseOnDivideByZero: true
        )
        let scaled = (btc * Decimal(Self.satoshisPerBTC) as NSDecimalNumber)
            .rounding(accordingToBehavior: handler)
        self.satoshis = scaled.int64Value
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Decimal.self)
        self.init(btc: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(btc)
    }

    // MARK: - AdditiveArithmetic

    public static var zero: BTCAmount { BTCAmount(satoshis: 0) }

    public static func + (lhs: BTCAmount, rhs: BTCAmount) -> BTCAmount {
        let (result, overflow) = lhs.satoshis.addingReportingOverflow(rhs.satoshis)
        precondition(!overflow, "BTCAmount addition overflow")
        return BTCAmount(satoshis: result)
    }

    public static func - (lhs: BTCAmount, rhs: BTCAmount) -> BTCAmount {
        let (result, overflow) = lhs.satoshis.subtractingReportingOverflow(rhs.satoshis)
        precondition(!overflow, "BTCAmount subtraction overflow")
        return BTCAmount(satoshis: result)
    }

    // MARK: - Additional Arithmetic

    public static prefix func - (value: BTCAmount) -> BTCAmount {
        let (result, overflow) = (0 as Int64).subtractingReportingOverflow(value.satoshis)
        precondition(!overflow, "BTCAmount negation overflow")
        return BTCAmount(satoshis: result)
    }

    public static func * (lhs: BTCAmount, rhs: Int64) -> BTCAmount {
        let (result, overflow) = lhs.satoshis.multipliedReportingOverflow(by: rhs)
        precondition(!overflow, "BTCAmount multiplication overflow")
        return BTCAmount(satoshis: result)
    }

    // MARK: - CustomStringConvertible

    public var description: String { "\(btc) BTC" }

    // MARK: - Hashable + Equatable + Comparable

    public func hash(into hasher: inout Hasher) { hasher.combine(satoshis) }

    public static func == (lhs: BTCAmount, rhs: BTCAmount) -> Bool {
        lhs.satoshis == rhs.satoshis
    }

    public static func < (lhs: BTCAmount, rhs: BTCAmount) -> Bool {
        lhs.satoshis < rhs.satoshis
    }
}
