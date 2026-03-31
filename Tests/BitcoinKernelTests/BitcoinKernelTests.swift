import Testing
import BitcoinKernel

@Suite("BitcoinKernel Tests")
struct BitcoinKernelTests {

    @Test("Kernel context creation succeeds")
    func createContext() {
        #expect(BitcoinKernel.verify())
    }
}
