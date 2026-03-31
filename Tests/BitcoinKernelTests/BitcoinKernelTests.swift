import Testing
import BitcoinKernel

@Test func contextOptionsCreateDestroy() {
    let options = BitcoinKernel.createContextOptions()
    #expect(options != nil)
    if let options {
        BitcoinKernel.destroyContextOptions(options)
    }
}
