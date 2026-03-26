import Testing
import Foundation
@testable import Bitcoin
import bitcoind

// MARK: - Shared Daemon Lifecycle

/// Manages a single daemon instance shared across all RPC bridge test suites.
/// The daemon starts once and shuts down when the process exits.
private enum DaemonFixture {
    private static let startOnce: Void = {
        Daemon.start([
            "-server=1",
            "-rpcbind=0.0.0.0",
            "-rpcallowip=127.0.0.1",
            "-rpcport=18443",
            "-rpcauth=111:14c1e13a71b7d6a4dab6c9d8f107bb5b$73b9fbbd71dbbb1476efa6da7b37dde5111153a17ccb5fdef79537d276fd03d4",
            "-regtest",
            "-prune=550",
        ])
        // Wait for the RPC server to become reachable
        Thread.sleep(forTimeInterval: 5)
    }()

    static func ensureRunning() {
        _ = startOnce
        _ = shutdownOnce
    }

    /// Register a one-time atexit handler that gracefully shuts down the daemon
    /// so the process exits cleanly (no signal 6 / libc++abi termination).
    private static let shutdownOnce: Void = {
        atexit {
            bitcoin_rpc_reset()
            raise(SIGTERM)
            Daemon.waitUntilStopped()
        }
    }()

    static func makeClient() -> APIClient {
        APIClient(
            url: URL(string: "http://localhost:18443")!,
            username: "111",
            password: "222"
        )
    }

    /// Bootstrap the direct RPC bridge via one HTTP call to _bridge_init.
    static func bootstrap() async throws {
        guard bitcoin_rpc_ready() == 0 else { return }
        let request = JSONRPCRequest(method: "_bridge_init", params: [])
        let service = JSONRPCService(
            url: URL(string: "http://localhost:18443")!,
            username: "111",
            password: "222"
        )
        let result: String = try await service.send(request: request)
        #expect(result == "ok")
    }
}

// MARK: - 1. Bridge Lifecycle

@Suite("Bridge Lifecycle", .serialized)
struct BridgeLifecycleTests {

    init() {
        DaemonFixture.ensureRunning()
    }

    @Test("Bridge is not ready before bootstrap")
    func notReadyBeforeBootstrap() {
        #expect(bitcoin_rpc_ready() == 0)
    }

    @Test("bitcoin_rpc returns nil before bootstrap")
    func rpcReturnsNilBeforeBootstrap() {
        let result = "getblockcount".withCString { method in
            "[]".withCString { params in
                bitcoin_rpc(method, params)
            }
        }
        #expect(result == nil)
    }

    @Test("Bootstrap via HTTP _bridge_init")
    func bootstrapViaHTTP() async throws {
        try await DaemonFixture.bootstrap()
        #expect(bitcoin_rpc_ready() == 1)
    }

    @Test("Bootstrap is idempotent")
    func bootstrapIsIdempotent() async throws {
        try await DaemonFixture.bootstrap()
        // Second call should be a no-op
        try await DaemonFixture.bootstrap()
        #expect(bitcoin_rpc_ready() == 1)
    }
}

// MARK: - 2. Direct RPC Parity

@Suite("Direct RPC Parity", .serialized)
struct DirectRPCParityTests {

    let client: APIClient

    init() async throws {
        DaemonFixture.ensureRunning()
        try await DaemonFixture.bootstrap()
        client = DaemonFixture.makeClient()
    }

    @Test("getblockcount via direct bridge")
    func directGetBlockCount() async throws {
        let count: Int = try await client.send(.getBlockCount)
        #expect(count >= 0)
    }

    @Test("getbestblockhash via direct bridge")
    func directGetBestBlockHash() async throws {
        let hash: String = try await client.send(.getBestBlockHash)
        #expect(hash.count == 64, "Block hash should be 64 hex characters")
    }

    @Test("getblockchaininfo via direct bridge")
    func directGetBlockchainInfo() async throws {
        let info: BlockchainInfo = try await client.send(.getBlockchainInfo)
        #expect(!info.chain.isEmpty)
        #expect(info.blocks >= 0)
    }

    @Test("getblock (verbosity 1) via direct bridge")
    func directGetBlock() async throws {
        let hash = "0f9188f13cb7b2c71f2a335e3a4fc328bf5beb436012afca590b1a11466e2206"
        let block: Block = try await client.send(.getBlock, params: [hash, 1])
        #expect(block.hash == hash)
    }

    @Test("getblock (verbosity 2) via direct bridge")
    func directGetBlockWithTransactions() async throws {
        let hash = "0f9188f13cb7b2c71f2a335e3a4fc328bf5beb436012afca590b1a11466e2206"
        let block: BlockWithTransactions = try await client.send(.getBlock, params: [hash, 2])
        #expect(block.hash == hash)
    }

    @Test("Invalid method returns error envelope, not crash")
    func invalidMethodReturnsError() throws {
        let ptr = "nonexistent_method_xyz".withCString { method in
            "[]".withCString { params in
                bitcoin_rpc(method, params)
            }
        }
        let unwrapped = try #require(ptr, "Should return error envelope, not nil")
        defer { bitcoin_free(UnsafeMutableRawPointer(unwrapped)) }

        let json = String(cString: unwrapped)
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        #expect(response.error != nil)
    }
}

// MARK: - 3. Transport Auto-Detection

@Suite("Transport Auto-Detection", .serialized)
struct TransportAutoDetectionTests {

    let client: APIClient

    init() async throws {
        DaemonFixture.ensureRunning()
        try await DaemonFixture.bootstrap()
        client = DaemonFixture.makeClient()
    }

    @Test("send() uses direct bridge when ready")
    func sendUsesDirectWhenReady() async throws {
        #expect(bitcoin_rpc_ready() == 1)
        let count: Int = try await client.send(.getBlockCount)
        #expect(count >= 0)
    }

    @Test("reset closes gate; bitcoin_rpc returns nil; send falls back to HTTP")
    func resetClosesGateAndFallsBack() async throws {
        bitcoin_rpc_reset()
        #expect(bitcoin_rpc_ready() == 0)

        let ptr = "getblockcount".withCString { method in
            "[]".withCString { params in
                bitcoin_rpc(method, params)
            }
        }
        #expect(ptr == nil)

        // send() should fall back to HTTP
        let count: Int = try await client.send(.getBlockCount)
        #expect(count >= 0)

        // Re-bootstrap for other suites
        try await DaemonFixture.bootstrap()
    }
}
