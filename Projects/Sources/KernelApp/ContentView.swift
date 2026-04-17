import BitcoinKernel
import SwiftUI

struct ContentView: View {
    let chains: [ChainType] = [.mainnet, .testnet, .regtest, .signet]
    @State private var torViewModel = TorViewModel(subsystem: "dev.21.KernelApp")
    @AppStorage("tor_enabled") private var torEnabled = false

    var body: some View {
        NavigationStack {
            List {
                Section("Chain Types") {
                    ForEach(chains, id: \.self) { chain in
                        Text(String(describing: chain))
                    }
                }

                Section {
                    Toggle("Tor", isOn: $torEnabled)
                        .onChange(of: torEnabled) { _, enabled in
                            if enabled {
                                torViewModel.start()
                            } else {
                                torViewModel.stop()
                            }
                        }

                    TorStatusView(viewModel: torViewModel)
                } header: {
                    Label("Tor", systemImage: "network")
                }
            }
            .navigationTitle("BitcoinKernel")
        }
        .task {
            if UserDefaults.standard.bool(forKey: "tor_enabled") {
                torViewModel.start()
            }
        }
    }
}

#Preview {
    ContentView()
}
