//
//  BTCAmount.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
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
/// ```swift
/// let amount = BTCAmount(satoshis: 100_000_000) // 1 BTC
/// print(amount.btc) // 1
/// print(amount)      // "1 BTC"
///
/// let fee = BTCAmount(btc: Decimal(string: "0.0001")!)
/// print(fee.satoshis) // 10000
/// ```
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

    /// The zero amount. Additive identity for `AdditiveArithmetic`.
    public static var zero: BTCAmount { BTCAmount(satoshis: 0) }

    /// Adds two amounts.
    ///
    /// - Parameters:
    ///   - lhs: The first amount.
    ///   - rhs: The second amount.
    /// - Returns: The sum, in satoshis.
    /// - Precondition: The sum fits in `Int64`; traps on overflow.
    public static func + (lhs: BTCAmount, rhs: BTCAmount) -> BTCAmount {
        let (result, overflow) = lhs.satoshis.addingReportingOverflow(rhs.satoshis)
        precondition(!overflow, "BTCAmount addition overflow")
        return BTCAmount(satoshis: result)
    }

    /// Subtracts one amount from another.
    ///
    /// - Parameters:
    ///   - lhs: The amount to subtract from.
    ///   - rhs: The amount to subtract.
    /// - Returns: The difference, in satoshis. May be negative.
    /// - Precondition: The difference fits in `Int64`; traps on overflow.
    public static func - (lhs: BTCAmount, rhs: BTCAmount) -> BTCAmount {
        let (result, overflow) = lhs.satoshis.subtractingReportingOverflow(rhs.satoshis)
        precondition(!overflow, "BTCAmount subtraction overflow")
        return BTCAmount(satoshis: result)
    }

    // MARK: - Additional Arithmetic

    /// Negates an amount.
    ///
    /// - Parameter value: The amount to negate.
    /// - Returns: A ``BTCAmount`` with `-value.satoshis`.
    /// - Precondition: `value.satoshis != Int64.min`; traps on overflow.
    public static prefix func - (value: BTCAmount) -> BTCAmount {
        let (result, overflow) = (0 as Int64).subtractingReportingOverflow(value.satoshis)
        precondition(!overflow, "BTCAmount negation overflow")
        return BTCAmount(satoshis: result)
    }

    /// Multiplies an amount by an integer scalar.
    ///
    /// - Parameters:
    ///   - lhs: The amount to scale.
    ///   - rhs: The integer multiplier.
    /// - Returns: A ``BTCAmount`` with `lhs.satoshis * rhs`.
    /// - Precondition: The product fits in `Int64`; traps on overflow.
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
