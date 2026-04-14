import BitcoinKernel
import SwiftUI

struct ContentView: View {
    let chains: [ChainType] = [.mainnet, .testnet, .regtest, .signet]

    var body: some View {
        NavigationStack {
            List {
                Section("Chain Types") {
                    ForEach(chains, id: \.self) { chain in
                        Text(String(describing: chain))
                    }
                }
            }
            .navigationTitle("BitcoinKernel")
        }
    }
}

#Preview {
    ContentView()
}
