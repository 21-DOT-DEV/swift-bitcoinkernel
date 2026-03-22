import XCTest
import Bitcoin


final class BitcoinTests: XCTestCase {

    // This will run once before any test methods in this class are executed
    override class func setUp() {
        super.setUp()

        // Code you want to run once before all tests
        Task{
            print("Starting Bitcoin...")

            Daemon.start(
                [
                    "-server=1",
                    "-rpcbind=0.0.0.0",
                    "-rpcallowip=127.0.0.1",
                    "-rpcport=8332",
                    "-rpcauth=111:14c1e13a71b7d6a4dab6c9d8f107bb5b$73b9fbbd71dbbb1476efa6da7b37dde5111153a17ccb5fdef79537d276fd03d4",
                    "-prune=550",
                    "-blockfilterindex=1"
                ]
            )
        }
        
        // Wait for the daemon to start (adjust the sleep time as needed)
        Thread.sleep(forTimeInterval: 5)
    }

    func testExample() async throws {
        // XCTest Documentation
        // https://developer.apple.com/documentation/xctest

        // Defining Test Cases and Test Methods
        // https://developer.apple.com/documentation/xctest/defining_test_cases_and_test_methods

        let client = APIClient(
            url: URL(string: "http://localhost:8332")!,
            username: "111",
            password: "222"
        )

        // Retry logic
        let maxRetries = 5
        var retryCount = 0

        while retryCount < maxRetries {
            do {
                _ = try await client.getBlock(hash: "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f", verbosity: .jsonWithTransactions)
                break
            } catch {
                print("Connection attempt \(retryCount + 1) failed: \(error)")
                retryCount += 1
                if retryCount < maxRetries {
                    try await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds before retrying
                }
            }
        }
    }
}
