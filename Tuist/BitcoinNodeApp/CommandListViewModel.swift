//
//  CommandListViewModel.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import BitcoinWrapper
import SwiftUI

//{"balance":0.000000000000000,"blocks":59952,"connections":48,"proxy":"","generate":false,
//     "genproclimit":-1,"difficulty":16.61907875185736}

final class CommandListViewModel: ObservableObject {
    @Published var commands: [Command] = []

    init() {
        // Initialize your commands here
        self.commands = [
            Command(title: "RPC GetBestBlockHash", action: {
                Task {
                    let response: String = try await APIClient().command(.getBestBlockHash)
                    print(response)
                }
            }),
            Command(title: "RPC GetBlockchainInfo", action: {
                Task {
                    let response: String = try await APIClient().command(.getBlockchainInfo)
                    print(response)
                }
            }),
            Command(title: "Daemon help", action: { Daemon.start(["-help"])}),
            Command(title: "Daemon start", action: { Task { Daemon.start(["-rpcauth=111:2dbf38080910790185b22905795c516b$8a233a0796922ff51047d663347d04d3ef3f1b415d1a40584158ea2e717a6f76", "-prune=550", "-blockfilterindex=1"]) } }),
        ]
    }
}
