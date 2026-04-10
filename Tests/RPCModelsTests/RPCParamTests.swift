import Testing
import Foundation
@testable import RPCModels

@Suite("RPCParam")
struct RPCParamTests {

    // MARK: - Test Helper

    /// Assert params encode to expected JSON string.
    func assertParamsEncode(
        to expected: String, params: [RPCParam],
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let data = try JSONEncoder().encode(params)
        let json = try #require(String(data: data, encoding: .utf8), sourceLocation: sourceLocation)
        #expect(json == expected, sourceLocation: sourceLocation)
    }

    // MARK: - Primitive Encoding

    @Test("Encodes string")
    func encodeString() throws {
        try assertParamsEncode(to: #"["hello"]"#, params: [.string("hello")])
    }

    @Test("Encodes int")
    func encodeInt() throws {
        try assertParamsEncode(to: "[42]", params: [.int(42)])
    }

    @Test("Encodes int64")
    func encodeInt64() throws {
        try assertParamsEncode(to: "[9999999999]", params: [.int64(9_999_999_999)])
    }

    @Test("Encodes double")
    func encodeDouble() throws {
        try assertParamsEncode(to: "[3.14]", params: [.double(3.14)])
    }

    @Test("Encodes bool true")
    func encodeBoolTrue() throws {
        try assertParamsEncode(to: "[true]", params: [.bool(true)])
    }

    @Test("Encodes bool false")
    func encodeBoolFalse() throws {
        try assertParamsEncode(to: "[false]", params: [.bool(false)])
    }

    @Test("Encodes null")
    func encodeNull() throws {
        try assertParamsEncode(to: "[null]", params: [.null])
    }

    // MARK: - Mixed Params

    @Test("Encodes mixed param array")
    func encodeMixed() throws {
        try assertParamsEncode(
            to: #"["abc",true,42]"#,
            params: [.string("abc"), .bool(true), .int(42)]
        )
    }

    @Test("Empty params array")
    func encodeEmpty() throws {
        try assertParamsEncode(to: "[]", params: [])
    }

    // MARK: - .encodable

    @Test("Encodes Encodable struct via .encodable")
    func encodeEncodableStruct() throws {
        struct TxInput: Encodable, Sendable {
            let txid: String
            let vout: Int
        }
        let inputs = [TxInput(txid: "abc123", vout: 0)]
        let data = try JSONEncoder().encode([RPCParam.encodable(inputs)])
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("abc123"))
        #expect(json.contains("vout"))
    }

    @Test("Encodes dictionary via .encodable")
    func encodeEncodableDictionary() throws {
        let outputs: [String: Int] = ["addr1": 100]
        let data = try JSONEncoder().encode([RPCParam.encodable(outputs)])
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("addr1"))
        #expect(json.contains("100"))
    }

    @Test("BTCAmount in .encodable dictionary encodes as number")
    func encodeBTCAmountInDictionary() throws {
        let outputs: [String: BTCAmount] = ["addr1": BTCAmount(btc: Decimal(string: "0.01")!)]
        let data = try JSONEncoder().encode([RPCParam.encodable(outputs)])
        let json = try #require(String(data: data, encoding: .utf8))
        // Must be a JSON number, not a string
        #expect(json.contains("0.01"))
        #expect(!json.contains("\"0.01\""))
    }
}
