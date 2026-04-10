import Testing
import Foundation
@testable import RPCModels

@Suite("UnixTimestamp")
struct UnixTimestampTests {

    // MARK: - Core-derived vectors

    @Test("Core vector: Bitcoin genesis block nTime = 1231006505 (chainparams.cpp)")
    func genesisBlockTime() throws {
        // CreateGenesisBlock(1231006505, ...) in chainparams.cpp:134
        let ts = UnixTimestamp(seconds: 1_231_006_505)
        #expect(ts.seconds == 1_231_006_505)
        #expect(ts.date == Date(timeIntervalSince1970: 1_231_006_505))
    }

    @Test("Core vector: genesis mediantime = 0 sentinel (getblockheader height=0)")
    func genesisMedianTimeZeroSentinel() throws {
        // Genesis block has mediantime=1231006505 in modern Core, but
        // 0 is used as sentinel for "not set" in several wallet fields.
        let ts = UnixTimestamp(seconds: 0)
        #expect(ts.seconds == 0)
        #expect(ts.date == Date(timeIntervalSince1970: 0))
    }

    @Test("Core vector: block #2016 retarget timestamp = 1233061996 (pow_tests.cpp)")
    func retargetTimestamp() throws {
        // From pow_tests.cpp: pindexLast.nTime = 1233061996 (Block #2015)
        let ts = UnixTimestamp(seconds: 1_233_061_996)
        #expect(ts.seconds == 1_233_061_996)
    }

    @Test("Core vector: block #1 timestamp = 1231469665")
    func block1Timestamp() throws {
        // Block 1: 2009-01-09T02:54:25Z
        let ts = UnixTimestamp(seconds: 1_231_469_665)
        #expect(ts.seconds == 1_231_469_665)
    }

    // MARK: - Codable

    @Test("Codable round-trip: encode then decode preserves seconds")
    func codableRoundTrip() throws {
        let original = UnixTimestamp(seconds: 1_231_006_505)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UnixTimestamp.self, from: data)
        #expect(original == decoded)
        #expect(decoded.seconds == 1_231_006_505)
    }

    @Test("Decodes from raw Int64 JSON")
    func decodesFromInt64() throws {
        let json = "1296688602"
        let ts = try JSONDecoder().decode(UnixTimestamp.self, from: Data(json.utf8))
        #expect(ts.seconds == 1_296_688_602)
    }

    // MARK: - ExpressibleByIntegerLiteral

    @Test("ExpressibleByIntegerLiteral: assign directly from integer")
    func integerLiteral() {
        let ts: UnixTimestamp = 1_231_006_505
        #expect(ts.seconds == 1_231_006_505)
    }

    @Test("ExpressibleByIntegerLiteral: zero literal")
    func zeroLiteral() {
        let ts: UnixTimestamp = 0
        #expect(ts.seconds == 0)
    }

    // MARK: - Date bridge

    @Test("date computed property returns correct Date")
    func dateProperty() {
        let ts = UnixTimestamp(seconds: 0)
        #expect(ts.date == Date(timeIntervalSince1970: 0))
    }

    @Test("init from Date")
    func initFromDate() {
        let date = Date(timeIntervalSince1970: 1_231_006_505)
        let ts = UnixTimestamp(date)
        #expect(ts.seconds == 1_231_006_505)
    }

    // MARK: - CustomStringConvertible (ISO 8601)

    @Test("description: genesis block formats as ISO 8601")
    func descriptionGenesis() {
        let ts = UnixTimestamp(seconds: 1_231_006_505)
        #expect(ts.description == "2009-01-03T18:15:05Z")
    }

    @Test("description: epoch zero formats as 1970")
    func descriptionEpochZero() {
        let ts: UnixTimestamp = 0
        #expect(ts.description == "1970-01-01T00:00:00Z")
    }

    // MARK: - Comparable

    @Test("Comparable: earlier < later")
    func comparable() {
        let earlier: UnixTimestamp = 100
        let later: UnixTimestamp = 200
        #expect(earlier < later)
        #expect(!(later < earlier))
        #expect(!(earlier < earlier))
    }

    // MARK: - Hashable

    @Test("Hashable: equal timestamps have equal hashes")
    func hashable() {
        let a = UnixTimestamp(seconds: 1_231_006_505)
        let b: UnixTimestamp = 1_231_006_505
        #expect(a.hashValue == b.hashValue)
    }
}
