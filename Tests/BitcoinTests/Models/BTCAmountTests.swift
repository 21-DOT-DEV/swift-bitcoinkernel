//
//  BTCAmountTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
import Foundation
@testable import Bitcoin

@Suite("BTCAmount")
struct BTCAmountTests {

    // MARK: - Round-trip

    @Test("Satoshi round-trip: 2.09999999 BTC = 209999999 sats")
    func satoshiRoundTrip() {
        let amount = BTCAmount(btc: Decimal(string: "2.09999999")!)
        #expect(amount.satoshis == 209_999_999)
        #expect(amount.btc == Decimal(string: "2.09999999")!)
    }

    @Test("Zero amount")
    func zeroAmount() {
        #expect(BTCAmount.zero.satoshis == 0)
        #expect(BTCAmount.zero.btc == 0)
    }

    @Test("Negative amount is valid")
    func negativeAmount() {
        let amount = BTCAmount(satoshis: -50_000_000)
        #expect(amount.satoshis == -50_000_000)
        #expect(amount.btc == Decimal(string: "-0.5")!)
    }

    // MARK: - 0.5-sat rounding

    @Test("0.000000005 BTC (0.5 sats) rounds to 1 with .plain rounding")
    func halfSatRounding() {
        let amount = BTCAmount(btc: Decimal(string: "0.000000005")!)
        #expect(amount.satoshis == 1)
    }

    @Test("0.000000015 BTC (1.5 sats) rounds to 2 with .plain rounding")
    func oneAndHalfSatRounding() {
        let amount = BTCAmount(btc: Decimal(string: "0.000000015")!)
        #expect(amount.satoshis == 2)
    }

    // MARK: - Codable round-trip

    @Test("Codable round-trip: 0.30000001 BTC (Double precision regression tripwire)")
    func codableRoundTrip030000001() throws {
        let json = "0.30000001"
        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data(json.utf8))
        #expect(decoded.satoshis == 30_000_001)

        let encoded = try JSONEncoder().encode(decoded)
        let reDecoded = try JSONDecoder().decode(Decimal.self, from: encoded)
        #expect(reDecoded == Decimal(string: "0.30000001")!)
    }

    @Test("Codable round-trip: 21000000.0 BTC (max supply)")
    func codableMaxSupply() throws {
        let json = "21000000.0"
        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data(json.utf8))
        #expect(decoded.satoshis == 2_100_000_000_000_000)
    }

    @Test("Codable round-trip: symmetric encode/decode")
    func codableSymmetric() throws {
        let original = BTCAmount(btc: Decimal(string: "1.23456789")!)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BTCAmount.self, from: data)
        #expect(original == decoded)
    }

    // MARK: - Request-path encoding (BTCAmount encodes as JSON number, not string)

    @Test("BTCAmount encodes as JSON number, not string")
    func encodesAsNumber() throws {
        let outputs: [String: BTCAmount] = ["addr1": BTCAmount(btc: Decimal(string: "0.01")!)]
        let data = try JSONEncoder().encode(outputs)
        let json = String(data: data, encoding: .utf8)!
        // Must be a number (0.01), not a string ("0.01")
        #expect(json.contains("0.01"))
        #expect(!json.contains("\"0.01\""))
    }

    // MARK: - Arithmetic

    @Test("Addition")
    func addition() {
        let a = BTCAmount(satoshis: 100)
        let b = BTCAmount(satoshis: 200)
        #expect((a + b).satoshis == 300)
    }

    @Test("Subtraction")
    func subtraction() {
        let a = BTCAmount(satoshis: 300)
        let b = BTCAmount(satoshis: 100)
        #expect((a - b).satoshis == 200)
    }

    @Test("Negation")
    func negation() {
        let a = BTCAmount(satoshis: 42)
        #expect((-a).satoshis == -42)
    }

    @Test("Multiplication by Int64")
    func multiplication() {
        let a = BTCAmount(satoshis: 10)
        #expect((a * 5).satoshis == 50)
    }

    // MARK: - Comparable + Hashable

    @Test("Comparable")
    func comparable() {
        let small = BTCAmount(satoshis: 1)
        let large = BTCAmount(satoshis: 2)
        #expect(small < large)
        #expect(!(large < small))
    }

    @Test("Hashable: equal amounts hash equally")
    func hashable() {
        let a = BTCAmount(satoshis: 42)
        let b = BTCAmount(satoshis: 42)
        #expect(a.hashValue == b.hashValue)
    }

    // MARK: - AdditiveArithmetic

    @Test("AdditiveArithmetic .zero works with reduce")
    func additiveArithmeticReduce() {
        let amounts = [BTCAmount(satoshis: 10), BTCAmount(satoshis: 20), BTCAmount(satoshis: 30)]
        let total = amounts.reduce(BTCAmount.zero, +)
        #expect(total.satoshis == 60)
    }

    // MARK: - Core vectors: Powers-of-10 ladder (util_tests.cpp FormatMoney/ParseMoney)

    @Test("Core vector: 0.00000001 BTC = 1 sat (COIN/100000000)")
    func coreVector1Sat() throws {
        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data("0.00000001".utf8))
        #expect(decoded.satoshis == 1)
        #expect(decoded.btc == Decimal(string: "0.00000001")!)
    }

    @Test("Core vector: 0.0000001 BTC = 10 sats (COIN/10000000)")
    func coreVector10Sats() throws {
        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data("0.0000001".utf8))
        #expect(decoded.satoshis == 10)
    }

    @Test("Core vector: 0.000001 BTC = 100 sats (COIN/1000000)")
    func coreVector100Sats() throws {
        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data("0.000001".utf8))
        #expect(decoded.satoshis == 100)
    }

    @Test("Core vector: 0.00001 BTC = 1000 sats (COIN/100000)")
    func coreVector1kSats() throws {
        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data("0.00001".utf8))
        #expect(decoded.satoshis == 1_000)
    }

    @Test("Core vector: 0.0001 BTC = 10000 sats (COIN/10000)")
    func coreVector10kSats() throws {
        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data("0.0001".utf8))
        #expect(decoded.satoshis == 10_000)
    }

    @Test("Core vector: 0.001 BTC = 100000 sats (COIN/1000)")
    func coreVector100kSats() throws {
        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data("0.001".utf8))
        #expect(decoded.satoshis == 100_000)
    }

    @Test("Core vector: 0.01 BTC = 1000000 sats (COIN/100)")
    func coreVector1mSats() throws {
        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data("0.01".utf8))
        #expect(decoded.satoshis == 1_000_000)
    }

    @Test("Core vector: 0.1 BTC = 10000000 sats (COIN/10)")
    func coreVector10mSats() throws {
        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data("0.1".utf8))
        #expect(decoded.satoshis == 10_000_000)
    }

    @Test("Core vector: 1.0 BTC = COIN")
    func coreVector1BTC() throws {
        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data("1.0".utf8))
        #expect(decoded.satoshis == 100_000_000)
    }

    @Test("Core vector: 10.0 BTC = COIN*10")
    func coreVector10BTC() throws {
        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data("10.0".utf8))
        #expect(decoded.satoshis == 1_000_000_000)
    }

    @Test("Core vector: 100.0 BTC = COIN*100")
    func coreVector100BTC() throws {
        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data("100.0".utf8))
        #expect(decoded.satoshis == 10_000_000_000)
    }

    @Test("Core vector: 1000.0 BTC = COIN*1000")
    func coreVector1kBTC() throws {
        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data("1000.0".utf8))
        #expect(decoded.satoshis == 100_000_000_000)
    }

    @Test("Core vector: 10000.0 BTC = COIN*10000")
    func coreVector10kBTC() throws {
        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data("10000.0".utf8))
        #expect(decoded.satoshis == 1_000_000_000_000)
    }

    @Test("Core vector: 100000.0 BTC = COIN*100000")
    func coreVector100kBTC() throws {
        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data("100000.0".utf8))
        #expect(decoded.satoshis == 10_000_000_000_000)
    }

    @Test("Core vector: 1000000.0 BTC = COIN*1000000")
    func coreVector1mBTC() throws {
        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data("1000000.0".utf8))
        #expect(decoded.satoshis == 100_000_000_000_000)
    }

    @Test("Core vector: 10000000.0 BTC = COIN*10000000")
    func coreVector10mBTC() throws {
        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data("10000000.0".utf8))
        #expect(decoded.satoshis == 1_000_000_000_000_000)
    }

    // MARK: - Core vector: canonical mixed value (util_tests.cpp)

    @Test("Core vector: 12345.6789 BTC = (COIN/10000)*123456789")
    func coreVectorCanonicalMixed() throws {
        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data("12345.6789".utf8))
        // (100_000_000 / 10_000) * 123_456_789 = 10_000 * 123_456_789 = 1_234_567_890_000
        #expect(decoded.satoshis == 1_234_567_890_000)
    }

    // MARK: - Core vectors: Int64 boundaries (util_tests.cpp FormatMoney)

    @Test("Core vector: Int64.max satoshis = 92233720368.54775807 BTC")
    func coreVectorInt64Max() throws {
        let amount = BTCAmount(satoshis: Int64.max) // 9_223_372_036_854_775_807
        #expect(amount.btc == Decimal(string: "92233720368.54775807")!)
    }

    @Test("Core vector: Int64.max-1 satoshis = 92233720368.54775806 BTC")
    func coreVectorInt64MaxMinus1() throws {
        let amount = BTCAmount(satoshis: Int64.max - 1)
        #expect(amount.btc == Decimal(string: "92233720368.54775806")!)
    }

    @Test("Core vector: Int64.max-2 satoshis = 92233720368.54775805 BTC")
    func coreVectorInt64MaxMinus2() throws {
        let amount = BTCAmount(satoshis: Int64.max - 2)
        #expect(amount.btc == Decimal(string: "92233720368.54775805")!)
    }

    @Test("Core vector: Int64.max-3 satoshis = 92233720368.54775804 BTC")
    func coreVectorInt64MaxMinus3() throws {
        let amount = BTCAmount(satoshis: Int64.max - 3)
        #expect(amount.btc == Decimal(string: "92233720368.54775804")!)
    }

    @Test("Core vector: Int64.min+3 satoshis = -92233720368.54775805 BTC")
    func coreVectorInt64MinPlus3() throws {
        let amount = BTCAmount(satoshis: Int64.min + 3)
        #expect(amount.btc == Decimal(string: "-92233720368.54775805")!)
    }

    @Test("Core vector: Int64.min+2 satoshis = -92233720368.54775806 BTC")
    func coreVectorInt64MinPlus2() throws {
        let amount = BTCAmount(satoshis: Int64.min + 2)
        #expect(amount.btc == Decimal(string: "-92233720368.54775806")!)
    }

    @Test("Core vector: Int64.min+1 satoshis = -92233720368.54775807 BTC")
    func coreVectorInt64MinPlus1() throws {
        let amount = BTCAmount(satoshis: Int64.min + 1)
        #expect(amount.btc == Decimal(string: "-92233720368.54775807")!)
    }

    @Test("Core vector: Int64.min satoshis = -92233720368.54775808 BTC")
    func coreVectorInt64Min() throws {
        let amount = BTCAmount(satoshis: Int64.min) // -9_223_372_036_854_775_808
        #expect(amount.btc == Decimal(string: "-92233720368.54775808")!)
    }

    // MARK: - Core vectors: Int64 boundary Codable round-trip

    @Test("Core vector: 92233720368.54775807 BTC decodes to Int64.max satoshis")
    func coreVectorInt64MaxDecode() throws {
        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data("92233720368.54775807".utf8))
        #expect(decoded.satoshis == Int64.max)
    }

    @Test("Core vector: Int64.max Codable round-trip is symmetric")
    func coreVectorInt64MaxRoundTrip() throws {
        let original = BTCAmount(satoshis: Int64.max)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BTCAmount.self, from: data)
        #expect(original == decoded)
    }

    // MARK: - Core vectors: MoneyRange (amount_tests.cpp)

    @Test("Core vector: MoneyRange — MAX_MONEY = 21000000 * COIN")
    func coreVectorMaxMoney() {
        let maxMoney = BTCAmount(satoshis: 21_000_000 * BTCAmount.satoshisPerBTC)
        #expect(maxMoney.satoshis == 2_100_000_000_000_000)
        #expect(maxMoney.btc == Decimal(string: "21000000")!)
    }

    @Test("Core vector: MoneyRange — 0 is in range")
    func coreVectorMoneyRangeZero() {
        let zero = BTCAmount(satoshis: 0)
        #expect(zero.satoshis >= 0 && zero.satoshis <= 21_000_000 * BTCAmount.satoshisPerBTC)
    }

    @Test("Core vector: MoneyRange — 1 is in range")
    func coreVectorMoneyRangeOne() {
        let one = BTCAmount(satoshis: 1)
        #expect(one.satoshis >= 0 && one.satoshis <= 21_000_000 * BTCAmount.satoshisPerBTC)
    }

    @Test("Core vector: MoneyRange — -1 is out of range")
    func coreVectorMoneyRangeNegative() {
        let neg = BTCAmount(satoshis: -1)
        #expect(!(neg.satoshis >= 0 && neg.satoshis <= 21_000_000 * BTCAmount.satoshisPerBTC))
    }

    @Test("Core vector: MoneyRange — MAX_MONEY+1 is out of range")
    func coreVectorMoneyRangeOverflow() {
        let over = BTCAmount(satoshis: 21_000_000 * BTCAmount.satoshisPerBTC + 1)
        #expect(!(over.satoshis >= 0 && over.satoshis <= 21_000_000 * BTCAmount.satoshisPerBTC))
    }

    // MARK: - Core vectors: sub-satoshi precision

    @Test("Core vector: 0.000000001 BTC (sub-satoshi) rounds to 0 sats")
    func coreVectorSubSatoshi() {
        let amount = BTCAmount(btc: Decimal(string: "0.000000001")!)
        #expect(amount.satoshis == 0)
    }

    @Test("Core vector: 0.000000004 BTC (0.4 sats) rounds to 0 sats")
    func coreVectorSubSatoshi04() {
        let amount = BTCAmount(btc: Decimal(string: "0.000000004")!)
        #expect(amount.satoshis == 0)
    }

    // MARK: - Core vectors: negative formatting (util_tests.cpp FormatMoney)

    @Test("Core vector: -1.0 BTC = -COIN satoshis")
    func coreVectorNegative1BTC() throws {
        let amount = BTCAmount(satoshis: -100_000_000)
        #expect(amount.btc == Decimal(string: "-1")!)

        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data("-1.0".utf8))
        #expect(decoded.satoshis == -100_000_000)
    }

    // MARK: - Core vectors: specific non-round values (rpc_tests.cpp rpc_format/parse_monetary_values)

    @Test("Core vector: 17622195 sats = 0.17622195 BTC")
    func coreVector17622195() throws {
        let amount = BTCAmount(satoshis: 17_622_195)
        #expect(amount.btc == Decimal(string: "0.17622195")!)

        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data("0.17622195".utf8))
        #expect(decoded.satoshis == 17_622_195)
    }

    @Test("Core vector: 50000000 sats = 0.5 BTC")
    func coreVector50m() throws {
        let amount = BTCAmount(satoshis: 50_000_000)
        #expect(amount.btc == Decimal(string: "0.5")!)

        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data("0.5".utf8))
        #expect(decoded.satoshis == 50_000_000)
    }

    @Test("Core vector: 89898989 sats = 0.89898989 BTC")
    func coreVector89898989() throws {
        let amount = BTCAmount(satoshis: 89_898_989)
        #expect(amount.btc == Decimal(string: "0.89898989")!)

        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data("0.89898989".utf8))
        #expect(decoded.satoshis == 89_898_989)
    }

    @Test("Core vector: 2099999999999990 sats = 20999999.9999999 BTC (near-max, trailing zero)")
    func coreVectorNearMaxTrailingZero() throws {
        let amount = BTCAmount(satoshis: 2_099_999_999_999_990)
        #expect(amount.btc == Decimal(string: "20999999.9999999")!)

        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data("20999999.9999999".utf8))
        #expect(decoded.satoshis == 2_099_999_999_999_990)
    }

    @Test("Core vector: 2099999999999999 sats = 20999999.99999999 BTC (near-max)")
    func coreVectorNearMax() throws {
        let amount = BTCAmount(satoshis: 2_099_999_999_999_999)
        #expect(amount.btc == Decimal(string: "20999999.99999999")!)

        let decoded = try JSONDecoder().decode(BTCAmount.self, from: Data("20999999.99999999".utf8))
        #expect(decoded.satoshis == 2_099_999_999_999_999)
    }

    // MARK: - Core vectors: powers-of-10 encode round-trip

    @Test("Core vector: powers-of-10 encode/decode round-trip")
    func coreVectorPowersOf10RoundTrip() throws {
        let vectors: [(String, Int64)] = [
            ("0.00000001", 1),
            ("0.0000001", 10),
            ("0.000001", 100),
            ("0.00001", 1_000),
            ("0.0001", 10_000),
            ("0.001", 100_000),
            ("0.01", 1_000_000),
            ("0.1", 10_000_000),
            ("1.0", 100_000_000),
            ("10.0", 1_000_000_000),
            ("100.0", 10_000_000_000),
            ("1000.0", 100_000_000_000),
            ("10000.0", 1_000_000_000_000),
            ("100000.0", 10_000_000_000_000),
            ("1000000.0", 100_000_000_000_000),
            ("10000000.0", 1_000_000_000_000_000),
        ]
        for (btcString, expectedSats) in vectors {
            let original = BTCAmount(satoshis: expectedSats)
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(BTCAmount.self, from: encoded)
            #expect(original == decoded, "Round-trip failed for \(btcString)")
        }
    }
}
