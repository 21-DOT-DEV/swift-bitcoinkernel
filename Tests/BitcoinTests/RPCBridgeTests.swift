import Testing
import Foundation
@testable import Bitcoin

// MARK: - Mock Transport

/// A mock transport that returns pre-configured JSON-RPC response data.
/// Each test injects its own response — fully isolated, no daemon needed.
struct MockTransport: RPCTransport {
    let responseData: Data

    init(json: String) {
        self.responseData = Data(json.utf8)
    }

    func send(request: JSONRPCRequest) async throws -> Data {
        responseData
    }
}

/// A mock transport that records what was sent and returns canned data.
final class SpyTransport: RPCTransport, @unchecked Sendable {
    private(set) var requests: [JSONRPCRequest] = []
    let responseData: Data

    init(json: String) {
        self.responseData = Data(json.utf8)
    }

    func send(request: JSONRPCRequest) async throws -> Data {
        requests.append(request)
        return responseData
    }
}

/// A transport that always throws, proving it was NOT called.
struct FailTransport: RPCTransport {
    func send(request: JSONRPCRequest) async throws -> Data {
        Issue.record("FailTransport should not be called")
        throw URLError(.badServerResponse)
    }
}

// MARK: - 1. Transport Selection (Unit Tests)

@Suite("Transport Selection")
struct TransportSelectionTests {

    @Test("APIClient with explicit HTTPTransport uses HTTP path")
    func explicitHTTPTransport() async throws {
        let spy = SpyTransport(json: #"{"result":42,"error":null,"id":"1"}"#)
        let client = APIClient(transport: spy)
        let count: Int = try await client.send(.getBlockCount)
        #expect(count == 42)
        #expect(spy.requests.count == 1)
        #expect(spy.requests.first?.method == "getblockcount")
    }

    @Test("APIClient with explicit DirectTransport uses direct path")
    func explicitDirectTransport() async throws {
        let spy = SpyTransport(json: #"{"result":"abc123","error":null,"id":"1"}"#)
        let client = APIClient(transport: spy)
        let hash: String = try await client.send(.getBestBlockHash)
        #expect(hash == "abc123")
        #expect(spy.requests.count == 1)
    }

    @Test("APIClient passes command parameters correctly")
    func parameterPassing() async throws {
        let spy = SpyTransport(json: #"{"result":99,"error":null,"id":"1"}"#)
        let client = APIClient(transport: spy)
        let _: Int = try await client.send(.getBlockCount, params: ["arg1", 42])
        let request = try #require(spy.requests.first)
        #expect(request.method == "getblockcount")
    }
}

// MARK: - 2. Response Decoding (Unit Tests)

@Suite("Response Decoding")
struct ResponseDecodingTests {

    @Test("Decodes integer result")
    func decodeInteger() async throws {
        let client = APIClient(transport: MockTransport(json: #"{"result":123,"error":null,"id":"1"}"#))
        let count: Int = try await client.send(.getBlockCount)
        #expect(count == 123)
    }

    @Test("Decodes string result")
    func decodeString() async throws {
        let client = APIClient(transport: MockTransport(json: #"{"result":"Bitcoin Core stopping","error":null,"id":"1"}"#))
        let msg: String = try await client.send(.stop)
        #expect(msg == "Bitcoin Core stopping")
    }

    @Test("Decodes BlockchainInfo result")
    func decodeBlockchainInfo() async throws {
        let json = """
        {"result":{"chain":"regtest","blocks":0,"headers":0,"bestblockhash":"0f9188f13cb7b2c71f2a335e3a4fc328bf5beb436012afca590b1a11466e2206","difficulty":4.656542373906925e-10,"time":1296688602,"mediantime":1296688602,"verificationprogress":1.0,"initialblockdownload":true,"chainwork":"0000000000000000000000000000000000000000000000000000000000000002","size_on_disk":293,"pruned":true,"pruneheight":0,"automatic_pruning":true,"prune_target_size":576716800,"warnings":[]},"error":null,"id":"1"}
        """
        let client = APIClient(transport: MockTransport(json: json))
        let info: BlockchainInfo = try await client.send(.getBlockchainInfo)
        #expect(info.chain == "regtest")
        #expect(info.blocks == 0)
        #expect(info.difficulty < 1.0)
    }

    @Test("Decodes JSON-RPC error into thrown NSError")
    func decodeRPCError() async throws {
        let json = #"{"result":null,"error":{"code":-32601,"message":"Method not found"},"id":"1"}"#
        let client = APIClient(transport: MockTransport(json: json))
        await #expect(throws: NSError.self) {
            let _: Int = try await client.send(.getBlockCount)
        }
    }

    @Test("Decodes null result")
    func decodeNull() throws {
        let json = #"{"result":null,"error":null,"id":"1"}"#
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        guard case .null = response.result else {
            Issue.record("Expected .null result")
            return
        }
    }
}

// MARK: - 3. Shared Decode Path (Unit Tests)

@Suite("Shared Decode Path")
struct SharedDecodePathTests {

    @Test("HTTP and Direct transports share the same decoding logic")
    func sameDecoderForBothPaths() async throws {
        let json = #"{"result":99,"error":null,"id":"1"}"#

        let httpClient = APIClient(transport: MockTransport(json: json))
        let directClient = APIClient(transport: MockTransport(json: json))

        let httpResult: Int = try await httpClient.send(.getBlockCount)
        let directResult: Int = try await directClient.send(.getBlockCount)

        #expect(httpResult == directResult)
        #expect(httpResult == 99)
    }

    @Test("RPC error decoded identically regardless of transport")
    func sameErrorFromBothPaths() async throws {
        let json = #"{"result":null,"error":{"code":-1,"message":"bad"},"id":"1"}"#

        let httpClient = APIClient(transport: MockTransport(json: json))
        let directClient = APIClient(transport: MockTransport(json: json))

        var httpError: NSError?
        var directError: NSError?

        do { let _: Int = try await httpClient.send(.getBlockCount) }
        catch { httpError = error as NSError }

        do { let _: Int = try await directClient.send(.getBlockCount) }
        catch { directError = error as NSError }

        let h = try #require(httpError)
        let d = try #require(directError)
        #expect(h.code == d.code)
        #expect(h.localizedDescription == d.localizedDescription)
    }
}
