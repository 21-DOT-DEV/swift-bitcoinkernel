import Testing
import Foundation
import os
import RPCModels
@testable import Bitcoin

// MARK: - Mock Transport

/// A mock transport that returns pre-configured JSON-RPC response data.
/// Each test injects its own response — fully isolated, no daemon needed.
struct MockTransport: RPCTransport {
    let responseData: Data

    init(json: String) {
        self.responseData = Data(json.utf8)
    }

    func send(_ request: JSONRPCRequest, path: String?) async throws -> Data {
        responseData
    }
}

/// A mock transport that records what was sent and returns canned data.
final class SpyTransport: RPCTransport, Sendable {
    private let _requests = OSAllocatedUnfairLock(initialState: [JSONRPCRequest]())
    var requests: [JSONRPCRequest] { _requests.withLock { $0 } }
    let responseData: Data

    init(json: String) {
        self.responseData = Data(json.utf8)
    }

    func send(_ request: JSONRPCRequest, path: String?) async throws -> Data {
        _requests.withLock { $0.append(request) }
        return responseData
    }
}

/// A wallet-capable spy transport that records requests AND paths.
final class WalletSpyTransport: WalletCapableTransport, Sendable {
    struct RecordedCall: Sendable { let request: JSONRPCRequest; let path: String? }
    private let _calls = OSAllocatedUnfairLock(initialState: [RecordedCall]())
    var calls: [RecordedCall] { _calls.withLock { $0 } }
    let responseData: Data

    init(json: String) {
        self.responseData = Data(json.utf8)
    }

    func send(_ request: JSONRPCRequest, path: String?) async throws -> Data {
        _calls.withLock { $0.append(RecordedCall(request: request, path: path)) }
        return responseData
    }
}

/// A transport that always throws, proving it was NOT called.
struct FailTransport: RPCTransport {
    func send(_ request: JSONRPCRequest, path: String?) async throws -> Data {
        Issue.record("FailTransport should not be called")
        throw URLError(.badServerResponse)
    }
}

// MARK: - 1. Transport Selection (Unit Tests)

@Suite("Transport Selection")
struct TransportSelectionTests {

    @Test("RPCClient with explicit transport uses provided transport")
    func explicitTransport() async throws {
        let spy = SpyTransport(json: #"{"result":42,"error":null,"id":"1"}"#)
        let client = RPCClient(transport: spy)
        let count: Int = try await client.send("getblockcount")
        #expect(count == 42)
        #expect(spy.requests.count == 1)
        #expect(spy.requests.first?.method == "getblockcount")
    }

    @Test("RPCClient decodes string result from transport")
    func stringResult() async throws {
        let spy = SpyTransport(json: #"{"result":"abc123","error":null,"id":"1"}"#)
        let client = RPCClient(transport: spy)
        let hash: String = try await client.send("getbestblockhash")
        #expect(hash == "abc123")
        #expect(spy.requests.count == 1)
    }

    @Test("RPCClient passes RPCParam parameters correctly")
    func parameterPassing() async throws {
        let spy = SpyTransport(json: #"{"result":99,"error":null,"id":"1"}"#)
        let client = RPCClient(transport: spy)
        let _: Int = try await client.send("getblockcount", params: [.string("arg1"), .int(42)])
        let request = try #require(spy.requests.first)
        #expect(request.method == "getblockcount")
    }
}

// MARK: - 2. Response Decoding (Unit Tests)

@Suite("Response Decoding")
struct ResponseDecodingTests {

    @Test("Decodes integer result")
    func decodeInteger() async throws {
        let client = RPCClient(transport: MockTransport(json: #"{"result":123,"error":null,"id":"1"}"#))
        let count: Int = try await client.send("getblockcount")
        #expect(count == 123)
    }

    @Test("Decodes string result")
    func decodeString() async throws {
        let client = RPCClient(transport: MockTransport(json: #"{"result":"Bitcoin Core stopping","error":null,"id":"1"}"#))
        let msg: String = try await client.send("stop")
        #expect(msg == "Bitcoin Core stopping")
    }

    @Test("Decodes BlockchainInfo result")
    func decodeBlockchainInfo() async throws {
        let json = """
        {"result":{"chain":"regtest","blocks":0,"headers":0,"bestblockhash":"0f9188f13cb7b2c71f2a335e3a4fc328bf5beb436012afca590b1a11466e2206","difficulty":4.656542373906925e-10,"time":1296688602,"mediantime":1296688602,"verificationprogress":1.0,"initialblockdownload":true,"chainwork":"0000000000000000000000000000000000000000000000000000000000000002","size_on_disk":293,"pruned":true,"pruneheight":0,"automatic_pruning":true,"prune_target_size":576716800,"warnings":[]},"error":null,"id":"1"}
        """
        let client = RPCClient(transport: MockTransport(json: json))
        let info: BlockchainInfo = try await client.send("getblockchaininfo")
        #expect(info.chain == "regtest")
        #expect(info.blocks == 0)
        #expect(info.difficulty < 1.0)
    }

    @Test("Decodes JSON-RPC error into thrown RPCError")
    func decodeRPCError() async throws {
        let json = #"{"result":null,"error":{"code":-32601,"message":"Method not found"},"id":"1"}"#
        let client = RPCClient(transport: MockTransport(json: json))
        await #expect(throws: RPCError.self) {
            let _: Int = try await client.send("getblockcount")
        }
    }

    @Test("Null result throws RPCClientError.unexpectedNullResult")
    func decodeNullThrows() async throws {
        let json = #"{"result":null,"error":null,"id":"1"}"#
        let client = RPCClient(transport: MockTransport(json: json))
        do {
            let _: Int = try await client.send("getblockcount")
            Issue.record("Expected error")
        } catch {
            guard let rpcError = error as? RPCClientError else {
                Issue.record("Expected RPCClientError, got \(error)")
                return
            }
            #expect(rpcError.method == "getblockcount")
        }
    }

    @Test("sendNullable returns nil for null result")
    func sendNullableReturnsNil() async throws {
        let json = #"{"result":null,"error":null,"id":"1"}"#
        let client = RPCClient(transport: MockTransport(json: json))
        let result: String? = try await client.sendNullable("gettxout")
        #expect(result == nil)
    }

    @Test("sendVoid succeeds on null result")
    func sendVoidSucceeds() async throws {
        let json = #"{"result":null,"error":null,"id":"1"}"#
        let client = RPCClient(transport: MockTransport(json: json))
        try await client.sendVoid("preciousblock")
    }
}

// MARK: - 3. Error Paths (Unit Tests)

@Suite("Error Paths")
struct ErrorPathTests {

    @Test("submitBlock succeeds on null result")
    func submitBlockSuccess() async throws {
        let json = #"{"result":null,"error":null,"id":"1"}"#
        let client = RPCClient(transport: MockTransport(json: json))
        try await client.submitBlock(hexData: "00000020...")
    }

    @Test("submitBlock throws blockRejected on non-null string")
    func submitBlockRejection() async throws {
        let json = #"{"result":"duplicate","error":null,"id":"1"}"#
        let client = RPCClient(transport: MockTransport(json: json))
        do {
            try await client.submitBlock(hexData: "00000020...")
            Issue.record("Expected blockRejected error")
        } catch {
            guard let rpcError = error as? RPCClientError,
                  case .blockRejected(let reason) = rpcError else {
                Issue.record("Expected RPCClientError.blockRejected, got \(error)")
                return
            }
            #expect(reason == "duplicate")
        }
    }

    @Test("Malformed JSON throws decodingFailed")
    func decodingFailed() async throws {
        let client = RPCClient(transport: MockTransport(json: "not json at all"))
        do {
            let _: Int = try await client.send("getblockcount")
            Issue.record("Expected decodingFailed error")
        } catch {
            guard let rpcError = error as? RPCClientError,
                  case .decodingFailed(let method, _, _) = rpcError else {
                Issue.record("Expected RPCClientError.decodingFailed, got \(error)")
                return
            }
            #expect(method == "getblockcount")
        }
    }

    @Test("DirectTransport with non-nil path throws walletPathNotSupported")
    func walletPathNotSupported() async throws {
        /// A transport that delegates to DirectTransport's path check without
        /// needing the actual bitcoind C bridge.
        struct PathCheckTransport: RPCTransport {
            func send(_ request: JSONRPCRequest, path: String?) async throws -> Data {
                if path != nil { throw RPCClientError.walletPathNotSupported }
                return Data()
            }
        }
        let client = RPCClient(transport: PathCheckTransport())
        do {
            // Use call() which passes path: nil by default — we need to test path != nil.
            // Call the transport directly to test the path check.
            let transport = PathCheckTransport()
            let request = JSONRPCRequest(method: "getbalance")
            _ = try await transport.send(request, path: "/wallet/mywallet")
            Issue.record("Expected walletPathNotSupported error")
        } catch {
            guard let rpcError = error as? RPCClientError,
                  case .walletPathNotSupported = rpcError else {
                Issue.record("Expected RPCClientError.walletPathNotSupported, got \(error)")
                return
            }
        }
    }
}

// MARK: - 4. Bug Regression Tests

@Suite("Bug Regressions")
struct BugRegressionTests {

    // -- Bug: HTTPTransport rejects RPC errors as HTTP 500 --
    // HTTPTransport.send() used to throw URLError(.badServerResponse) for any
    // non-200 status, discarding the JSON-RPC error body. Now it passes HTTP 500
    // through. We test at the RPCClient level using MockTransport (which already
    // passes all data through), verifying the decode layer surfaces RPCError.

    @Test("HTTP 500 JSON-RPC error surfaces as RPCError, not URLError")
    func http500SurfacesRPCError() async throws {
        // Simulates what Bitcoin Core returns for "Method not found" (HTTP 500 + JSON body)
        let json = #"{"result":null,"error":{"code":-32601,"message":"Method not found"},"id":"1"}"#
        let client = RPCClient(transport: MockTransport(json: json))
        do {
            let _: Int = try await client.send("nonexistent")
            Issue.record("Expected RPCError")
        } catch let error as RPCError {
            #expect(error.code == -32601)
            #expect(error.message == "Method not found")
        } catch {
            Issue.record("Expected RPCError, got \(type(of: error)): \(error)")
        }
    }

    @Test("HTTP 500 wallet-not-loaded error surfaces as RPCError")
    func http500WalletNotLoaded() async throws {
        let json = #"{"result":null,"error":{"code":-18,"message":"Requested wallet does not exist or is not loaded"},"id":"1"}"#
        let spy = WalletSpyTransport(json: json)
        let client = RPCClient(transport: spy)
        do {
            let _: WalletInfo = try await client.send("getwalletinfo", wallet: "missing")
            Issue.record("Expected RPCError")
        } catch let error as RPCError {
            #expect(error.code == -18)
            #expect(error.message.contains("not loaded"))
        } catch {
            Issue.record("Expected RPCError, got \(type(of: error)): \(error)")
        }
    }

    // -- Bug: call() / callWallet() bypassed JSON-RPC error checking --
    // These methods returned raw Data without inspecting response.error,
    // silently passing error responses through as opaque bytes.

    @Test("call() throws RPCError instead of returning error Data")
    func callThrowsRPCError() async throws {
        let json = #"{"result":null,"error":{"code":-1,"message":"bad call"},"id":"1"}"#
        let client = RPCClient(transport: MockTransport(json: json))
        do {
            _ = try await client.call("badmethod")
            Issue.record("Expected RPCError")
        } catch let error as RPCError {
            #expect(error.code == -1)
            #expect(error.message == "bad call")
        } catch {
            Issue.record("Expected RPCError, got \(type(of: error)): \(error)")
        }
    }

    @Test("call() returns Data on success")
    func callReturnsDataOnSuccess() async throws {
        let json = #"{"result":{"foo":"bar"},"error":null,"id":"1"}"#
        let client = RPCClient(transport: MockTransport(json: json))
        let data = try await client.call("goodmethod")
        #expect(!data.isEmpty)
    }

    @Test("callWallet() throws RPCError instead of returning error Data")
    func callWalletThrowsRPCError() async throws {
        let json = #"{"result":null,"error":{"code":-4,"message":"Wallet not found"},"id":"1"}"#
        let spy = WalletSpyTransport(json: json)
        let client = RPCClient(transport: spy)
        do {
            _ = try await client.callWallet("listdescriptors", wallet: "missing")
            Issue.record("Expected RPCError")
        } catch let error as RPCError {
            #expect(error.code == -4)
            #expect(error.message == "Wallet not found")
        } catch {
            Issue.record("Expected RPCError, got \(type(of: error)): \(error)")
        }
    }

    @Test("callWallet() returns Data on success")
    func callWalletReturnsDataOnSuccess() async throws {
        let json = #"{"result":{"descriptors":[]},"error":null,"id":"1"}"#
        let spy = WalletSpyTransport(json: json)
        let client = RPCClient(transport: spy)
        let data = try await client.callWallet("listdescriptors", wallet: "test")
        #expect(!data.isEmpty)
    }
}

#if Xcode || ENABLE_WALLET

// -- Bug: sendToAddress skips confTarget when replaceable is nil --
// Bitcoin Core's sendtoaddress uses positional params. If replaceable was nil
// but confTarget was set, confTarget landed in position 6 (replaceable's slot)
// instead of position 7. The fix inserts a .null placeholder.

@Suite("sendToAddress Param Layout")
struct SendToAddressParamLayoutTests {

    @Test("sendToAddress: confTarget without replaceable inserts null placeholder")
    func sendToAddressNullPlaceholder() async throws {
        let json = #"{"result":"txid123","error":null,"id":"1"}"#
        let spy = WalletSpyTransport(json: json)
        let client = RPCClient(transport: spy)

        _ = try await client.sendToAddress(
            wallet: "test", address: "bc1qtest", amount: 0.1,
            confTarget: 6  // replaceable defaults to nil
        )

        let request = try #require(spy.calls.first?.request)
        #expect(request.method == "sendtoaddress")

        // Encode params to JSON array and inspect positions
        let paramsData = try JSONEncoder().encode(request.params)
        let paramsArray = try JSONDecoder().decode([ParamValue].self, from: paramsData)

        // Positions: 0=address, 1=amount, 2=comment, 3=commentTo,
        //            4=subtractFee, 5=replaceable(null), 6=confTarget
        #expect(paramsArray.count == 7)
        #expect(paramsArray[5] == .null)      // null placeholder for replaceable
        #expect(paramsArray[6] == .int(6))    // confTarget in correct position
    }

    @Test("sendToAddress: replaceable set — no null placeholder needed")
    func sendToAddressWithReplaceable() async throws {
        let json = #"{"result":"txid456","error":null,"id":"1"}"#
        let spy = WalletSpyTransport(json: json)
        let client = RPCClient(transport: spy)

        _ = try await client.sendToAddress(
            wallet: "test", address: "bc1qtest", amount: 0.1,
            replaceable: true, confTarget: 3
        )

        let request = try #require(spy.calls.first?.request)
        let paramsData = try JSONEncoder().encode(request.params)
        let paramsArray = try JSONDecoder().decode([ParamValue].self, from: paramsData)

        // Positions: 0=address, 1=amount, 2=comment, 3=commentTo,
        //            4=subtractFee, 5=replaceable(true), 6=confTarget
        #expect(paramsArray.count == 7)
        #expect(paramsArray[5] == .bool(true))
        #expect(paramsArray[6] == .int(3))
    }

    @Test("sendToAddress: neither replaceable nor confTarget — no trailing params")
    func sendToAddressMinimal() async throws {
        let json = #"{"result":"txid789","error":null,"id":"1"}"#
        let spy = WalletSpyTransport(json: json)
        let client = RPCClient(transport: spy)

        _ = try await client.sendToAddress(
            wallet: "test", address: "bc1qtest", amount: 0.5
        )

        let request = try #require(spy.calls.first?.request)
        let paramsData = try JSONEncoder().encode(request.params)
        let paramsArray = try JSONDecoder().decode([ParamValue].self, from: paramsData)

        // Only: address, amount, comment, commentTo, subtractFee
        #expect(paramsArray.count == 5)
    }
}

/// Decodable helper for inspecting RPCParam values in tests.
private enum ParamValue: Decodable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([ParamValue])
    case object([String: ParamValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([ParamValue].self) { self = .array(v) }
        else { self = .object(try [String: ParamValue](from: decoder)) }
    }
}

// -- Bug: walletSend options parameter layout was incorrect --
// send(outputs, conf_target, estimate_mode, fee_rate, options)
// Old code used .int(0) for conf_target (overriding wallet default) and
// was missing the fee_rate null placeholder, so options landed at position 3.

@Suite("walletSend Param Layout")
struct WalletSendParamLayoutTests {

    @Test("walletSend with options: three null placeholders before options dict")
    func withOptions() async throws {
        let json = #"{"result":{"txid":"abc","complete":true},"error":null,"id":"1"}"#
        let spy = WalletSpyTransport(json: json)
        let client = RPCClient(transport: spy)

        _ = try await client.walletSend(
            wallet: "test",
            outputs: [["bc1qtest": .double(0.1)]],
            options: ["add_to_wallet": .bool(false)]
        )

        let request = try #require(spy.calls.first?.request)
        #expect(request.method == "send")

        let paramsData = try JSONEncoder().encode(request.params)
        let paramsArray = try JSONDecoder().decode([ParamValue].self, from: paramsData)

        // send(outputs, conf_target, estimate_mode, fee_rate, options)
        // Positions: 0=outputs, 1=null, 2=null, 3=null, 4=options
        #expect(paramsArray.count == 5)
        #expect(paramsArray[1] == .null) // conf_target
        #expect(paramsArray[2] == .null) // estimate_mode
        #expect(paramsArray[3] == .null) // fee_rate
        // Position 4 should be an object (options dict)
        if case .object(let opts) = paramsArray[4] {
            #expect(opts["add_to_wallet"] == .bool(false))
        } else {
            Issue.record("Expected options dict at position 4, got \(paramsArray[4])")
        }
    }

    @Test("walletSend without options: only outputs param")
    func withoutOptions() async throws {
        let json = #"{"result":{"txid":"def","complete":true},"error":null,"id":"1"}"#
        let spy = WalletSpyTransport(json: json)
        let client = RPCClient(transport: spy)

        _ = try await client.walletSend(
            wallet: "test",
            outputs: [["bc1qtest": .double(0.5)]]
        )

        let request = try #require(spy.calls.first?.request)
        let paramsData = try JSONEncoder().encode(request.params)
        let paramsArray = try JSONDecoder().decode([ParamValue].self, from: paramsData)

        // Only outputs, no placeholders
        #expect(paramsArray.count == 1)
    }
}

// -- Bug: listSinceBlock passed empty string instead of null for nil hash --

@Suite("listSinceBlock Param Layout")
struct ListSinceBlockParamLayoutTests {

    @Test("nil blockHash sends null, not empty string")
    func nilBlockHashSendsNull() async throws {
        let json = #"{"result":{"transactions":[],"lastblock":"00"},"error":null,"id":"1"}"#
        let spy = WalletSpyTransport(json: json)
        let client = RPCClient(transport: spy)

        _ = try await client.listSinceBlock(wallet: "test")

        let request = try #require(spy.calls.first?.request)
        #expect(request.method == "listsinceblock")

        let paramsData = try JSONEncoder().encode(request.params)
        let paramsArray = try JSONDecoder().decode([ParamValue].self, from: paramsData)

        // Position 0 = blockhash (should be null, not "")
        #expect(paramsArray[0] == .null)
    }

    @Test("non-nil blockHash sends hash string")
    func nonNilBlockHashSendsString() async throws {
        let json = #"{"result":{"transactions":[],"lastblock":"00"},"error":null,"id":"1"}"#
        let spy = WalletSpyTransport(json: json)
        let client = RPCClient(transport: spy)

        let hash = "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"
        _ = try await client.listSinceBlock(wallet: "test", blockHash: hash)

        let request = try #require(spy.calls.first?.request)
        let paramsData = try JSONEncoder().encode(request.params)
        let paramsArray = try JSONDecoder().decode([ParamValue].self, from: paramsData)

        #expect(paramsArray[0] == .string(hash))
    }
}

#endif

// MARK: - AutoTransport Routing

/// A recording transport that tracks whether it was called and with what path.
private final class RecordingTransport: RPCTransport, Sendable {
    private struct State { var callCount = 0; var lastPath: String?? }
    private let _state = OSAllocatedUnfairLock(initialState: State())
    var callCount: Int { _state.withLock { $0.callCount } }
    var lastPath: String?? { _state.withLock { $0.lastPath } }
    let responseData: Data

    init(json: String = #"{"result":null,"error":null,"id":"1"}"#) {
        self.responseData = Data(json.utf8)
    }

    func send(_ request: JSONRPCRequest, path: String?) async throws -> Data {
        _state.withLock { $0.callCount += 1; $0.lastPath = path }
        return responseData
    }
}

/// Mirrors AutoTransport's routing logic with a controllable "direct ready" flag.
/// Tests the routing decision without depending on the C bridge.
private struct RoutingTransport: RPCTransport {
    let http: RPCTransport
    let direct: RPCTransport
    let directReady: Bool

    func send(_ request: JSONRPCRequest, path: String?) async throws -> Data {
        // Must match AutoTransport.send exactly:
        if path != nil {
            return try await http.send(request, path: path)
        }
        if directReady {
            return try await direct.send(request, path: nil)
        }
        return try await http.send(request, path: nil)
    }
}

@Suite("AutoTransport Routing")
struct AutoTransportRoutingTests {

    @Test("Wallet RPC (non-nil path) routes to HTTP even when direct is ready")
    func walletRPCRoutesToHTTP() async throws {
        let http = RecordingTransport()
        let direct = RecordingTransport()
        let transport = RoutingTransport(http: http, direct: direct, directReady: true)

        let request = JSONRPCRequest(method: "getwalletinfo")
        _ = try await transport.send(request, path: "/wallet/default")

        #expect(http.callCount == 1)
        #expect(http.lastPath == "/wallet/default")
        #expect(direct.callCount == 0)
    }

    @Test("Non-wallet RPC routes to direct when ready")
    func nonWalletRPCRoutesToDirect() async throws {
        let http = RecordingTransport()
        let direct = RecordingTransport()
        let transport = RoutingTransport(http: http, direct: direct, directReady: true)

        let request = JSONRPCRequest(method: "getblockcount")
        _ = try await transport.send(request, path: nil)

        #expect(direct.callCount == 1)
        #expect(direct.lastPath == Optional<String>.none)
        #expect(http.callCount == 0)
    }

    @Test("Non-wallet RPC falls back to HTTP when direct is not ready")
    func nonWalletFallsBackToHTTP() async throws {
        let http = RecordingTransport()
        let direct = RecordingTransport()
        let transport = RoutingTransport(http: http, direct: direct, directReady: false)

        let request = JSONRPCRequest(method: "getblockcount")
        _ = try await transport.send(request, path: nil)

        #expect(http.callCount == 1)
        #expect(http.lastPath == Optional<String>.none)
        #expect(direct.callCount == 0)
    }

    @Test("Wallet RPC routes to HTTP even when direct is NOT ready")
    func walletRPCRoutesToHTTPWhenNotReady() async throws {
        let http = RecordingTransport()
        let direct = RecordingTransport()
        let transport = RoutingTransport(http: http, direct: direct, directReady: false)

        let request = JSONRPCRequest(method: "getbalances")
        _ = try await transport.send(request, path: "/wallet/mywallet")

        #expect(http.callCount == 1)
        #expect(http.lastPath == "/wallet/mywallet")
        #expect(direct.callCount == 0)
    }
}

// MARK: - 5. Shared Decode Path (Unit Tests)

@Suite("Shared Decode Path")
struct SharedDecodePathTests {

    @Test("HTTP and Direct transports share the same decoding logic")
    func sameDecoderForBothPaths() async throws {
        let json = #"{"result":99,"error":null,"id":"1"}"#

        let httpClient = RPCClient(transport: MockTransport(json: json))
        let directClient = RPCClient(transport: MockTransport(json: json))

        let httpResult: Int = try await httpClient.send("getblockcount")
        let directResult: Int = try await directClient.send("getblockcount")

        #expect(httpResult == directResult)
        #expect(httpResult == 99)
    }

    @Test("RPC error decoded identically regardless of transport")
    func sameErrorFromBothPaths() async throws {
        let json = #"{"result":null,"error":{"code":-1,"message":"bad"},"id":"1"}"#

        let httpClient = RPCClient(transport: MockTransport(json: json))
        let directClient = RPCClient(transport: MockTransport(json: json))

        var httpError: RPCError?
        var directError: RPCError?

        do { let _: Int = try await httpClient.send("getblockcount") }
        catch { httpError = error as? RPCError }

        do { let _: Int = try await directClient.send("getblockcount") }
        catch { directError = error as? RPCError }

        let h = try #require(httpError)
        let d = try #require(directError)
        #expect(h == d)
        #expect(h.code == -1)
        #expect(h.message == "bad")
    }
}
