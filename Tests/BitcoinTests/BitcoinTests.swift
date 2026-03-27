import Testing
import Bitcoin
import Foundation

// MARK: - Shared Daemon Fixture

/// Manages the Bitcoin daemon lifecycle for integration tests.
///
/// The daemon starts exactly once across all tests via `startOnce`, and is
/// stopped gracefully via an `atexit` handler registered by `shutdownOnce`.
/// Both are triggered by `ensureRunning()` which each test suite calls from
/// its `init()`.
private enum DaemonFixture {
    static let auth = RPCAuth(
        rawString: "111:14c1e13a71b7d6a4dab6c9d8f107bb5b$73b9fbbd71dbbb1476efa6da7b37dde5111153a17ccb5fdef79537d276fd03d4"
    )!

    private static let startOnce: Void = {
        // try! is safe here: we know this config is valid.
        // If validation throws (ConfigError), it's a programmer error and a
        // crash with the typed error message is the right outcome.
        try! Daemon.start(with:
            BitcoinConfig.mainnet()
                .server()
                .rpcBind(.allInterfaces)
                .rpcAllowIP(.localhost)
                .rpcPort(8332)
                .rpcAuth(auth)
                .prune(.minimum)
                .blockFilterIndex(.all)
        )
        Thread.sleep(forTimeInterval: 5)
    }()

    /// Registers a one-time atexit handler that gracefully shuts down the
    /// daemon so the process exits cleanly.
    private static let shutdownOnce: Void = {
        atexit {
            let client = DaemonFixture.makeClient()
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                _ = try? await client.stop()
                semaphore.signal()
            }
            semaphore.wait()
            Daemon.waitUntilStopped()
        }
    }()

    static func ensureRunning() {
        _ = startOnce
        _ = shutdownOnce
    }

    static func makeClient() -> APIClient {
        APIClient(
            url: URL(string: "http://localhost:8332")!,
            username: "111",
            password: "222"
        )
    }
}

// MARK: - Bitcoin Integration Tests

@Suite("Bitcoin Integration", .serialized)
final class BitcoinTests {

    init() {
        DaemonFixture.ensureRunning()
    }

    @Test("getBlock returns genesis block via HTTP")
    func getGenesisBlock() async throws {
        let client = DaemonFixture.makeClient()

        let maxRetries = 5
        var retryCount = 0

        while retryCount < maxRetries {
            do {
                _ = try await client.getBlock(
                    hash: "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f",
                    verbosity: .jsonWithTransactions
                )
                return
            } catch {
                retryCount += 1
                if retryCount < maxRetries {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
        Issue.record("getBlock failed after \(maxRetries) retries")
    }
}
