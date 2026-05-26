// Boot Bitcoin Core's consensus-validation engine into a fresh regtest data
// directory and confirm the chainstate has loaded by reading the tip height.

import BitcoinKernel
import Foundation

// Pick a network. Regtest is the empty, no-internet chain — instant boot at genesis.
let params = ChainParameters(.regtest)
let options = ContextOptions()
options.setChainParams(params)
let context = try Context(options: options)

// Throwaway data directory inside the system temp dir.
let dataDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
    .path(percentEncoded: false)

let managerOptions = try ChainstateManagerOptions(
    context: context,
    dataDirectory: dataDirectory
)
let manager = try ChainstateManager(options: managerOptions)

print(manager.bestEntry.height)  // 0 on a fresh regtest directory
