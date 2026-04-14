//
//  ConfigurationView.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import SwiftUI

/// Internal RPC configuration for in-process HTTP communication (localhost only).
/// Port 8332 is always forced via ``-rpcport`` in ``buildArguments()`` so
/// non-mainnet networks (which default to different ports) work correctly.
///
/// Authentication uses Bitcoin Core's cookie mechanism — no hardcoded
/// credentials. The cookie file path is set via ``-rpccookiefile`` so the
/// app knows exactly where to read it, regardless of data directory or network.
enum InternalRPC {
    static let port: UInt16 = 8332
    static var url: URL { URL(string: "http://127.0.0.1:\(port)")! }

    /// Known cookie file path, passed to `bitcoind` via `-rpccookiefile`.
    /// Using the temporary directory is safe — Bitcoin Core deletes the
    /// cookie on shutdown, and the file is only valid for the daemon's
    /// lifetime.
    static var cookieFileURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bitcoin-rpc.cookie")
    }
}

enum BitcoinNetwork: String, CaseIterable, Identifiable {
    case mainnet = "Mainnet"
    case testnet = "Testnet"
    case signet = "Signet"
    case regtest = "Regtest"

    var id: String { rawValue }

    var argument: String? {
        switch self {
        case .mainnet: nil
        case .testnet: "-testnet"
        case .signet: "-signet"
        case .regtest: "-regtest"
        }
    }
}

enum NodeType: String, CaseIterable, Identifiable {
    case pruned = "Pruned"
    case archival = "Archival"
    case compactFilters = "Compact Block Filters"

    var id: String { rawValue }
}

struct ConfigurationView: View {
    var nodeViewModel: NodeViewModel

    // Network
    @AppStorage("bitcoin_network") private var network: String = BitcoinNetwork.mainnet.rawValue

    // Node Type
    @AppStorage("node_type") private var nodeType: String = NodeType.pruned.rawValue
    @AppStorage("prune_size_mb") private var pruneSizeMB: Double = 550

    // Privacy
    @AppStorage("tor_enabled") private var torEnabled = false
    @AppStorage("private_broadcast_enabled") private var privateBroadcastEnabled = false

    // Resources
    @AppStorage("max_mempool_mb") private var maxMempoolMB: Double = 300
    @AppStorage("max_connections") private var maxConnections: Double = 125
    @AppStorage("listen_enabled") private var listenEnabled = true

    // RPC
    @AppStorage("rpc_auth") private var rpcAuth = ""

    private var selectedNetwork: Binding<BitcoinNetwork> {
        Binding(
            get: { BitcoinNetwork(rawValue: network) ?? .mainnet },
            set: { network = $0.rawValue }
        )
    }

    private var selectedNodeType: Binding<NodeType> {
        Binding(
            get: { NodeType(rawValue: nodeType) ?? .pruned },
            set: { nodeType = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Network", selection: selectedNetwork) {
                        ForEach(BitcoinNetwork.allCases) { net in
                            Text(net.rawValue).tag(net)
                        }
                    }
                } header: {
                    Label("Network", systemImage: "globe")
                } footer: {
                    Text("Select the Bitcoin network to connect to. Restart required.")
                }

                Section {
                    Picker("Node Type", selection: selectedNodeType) {
                        ForEach(NodeType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    if selectedNodeType.wrappedValue == .pruned {
                        LabeledContent("Prune Size") {
                            Text("\(Int(pruneSizeMB)) MB")
                        }
                        Slider(value: $pruneSizeMB, in: 550...10000, step: 50)
                    }
                } header: {
                    Label("Node Type", systemImage: "server.rack")
                } footer: {
                    switch selectedNodeType.wrappedValue {
                    case .pruned:
                        Text("Reduces disk usage by pruning old block data. Minimum 550 MB.")
                    case .archival:
                        Text("Stores the complete blockchain. Requires significant disk space.")
                    case .compactFilters:
                        Text("Enables BIP 157/158 compact block filters for light client support.")
                    }
                }

                Section {
                    Toggle("Tor", isOn: $torEnabled)
                    Toggle("Private Broadcast", isOn: $privateBroadcastEnabled)
                } header: {
                    Label("Privacy", systemImage: "lock.shield")
                } footer: {
                    Text("Route connections through Tor for enhanced privacy. Private broadcast sends transactions without revealing your IP.")
                }

                Section {
                    LabeledContent("Max Mempool") {
                        Text("\(Int(maxMempoolMB)) MB")
                    }
                    Slider(value: $maxMempoolMB, in: 5...2000, step: 5)

                    LabeledContent("Max Connections") {
                        Text("\(Int(maxConnections))")
                    }
                    Slider(value: $maxConnections, in: 1...1000, step: 1)

                    Toggle("Accept Inbound Connections", isOn: $listenEnabled)
                } header: {
                    Label("Resources", systemImage: "cpu")
                }

                Section {
                    TextField("rpcauth string", text: $rpcAuth)
                        .font(.body.monospaced())
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                } header: {
                    Label("RPC Authentication", systemImage: "key")
                } footer: {
                    Text("Format: username:salt$hash. Generated with rpcauth.py.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Configuration")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NodeToolbarMenu(nodeViewModel: nodeViewModel, buildArguments: Self.buildArguments)
                }
            }
            .disabled(nodeViewModel.isRunning)
            .safeAreaInset(edge: .bottom) {
                if nodeViewModel.isRunning {
                    Text("Stop the node to change settings")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                }
            }
        }
    }

    /// Build daemon arguments from current configuration stored in UserDefaults.
    static func buildArguments() -> [String] {
        let defaults = UserDefaults.standard
        var args: [String] = [
            "-server",
            "-rpcbind=127.0.0.1",
            "-rpcallowip=127.0.0.1",
            "-rpcport=\(InternalRPC.port)",
            "-rpccookiefile=\(InternalRPC.cookieFileURL.path)",
        ]

        let network = BitcoinNetwork(rawValue: defaults.string(forKey: "bitcoin_network") ?? "") ?? .mainnet
        if let networkArg = network.argument {
            args.append(networkArg)
        }

        let nodeType = NodeType(rawValue: defaults.string(forKey: "node_type") ?? "") ?? .pruned
        switch nodeType {
        case .pruned:
            let pruneSizeMB = defaults.double(forKey: "prune_size_mb")
            args.append("-prune=\(Int(pruneSizeMB > 0 ? pruneSizeMB : 550))")
        case .archival:
            break
        case .compactFilters:
            args.append("-blockfilterindex=1")
            args.append("-peerblockfilters=1")
        }

        if defaults.bool(forKey: "tor_enabled") {
            args.append("-proxy=127.0.0.1:9050")
        }

        if defaults.bool(forKey: "private_broadcast_enabled") {
            args.append("-privatebroadcast")
        }

        let maxMempoolMB = defaults.double(forKey: "max_mempool_mb")
        args.append("-maxmempool=\(Int(maxMempoolMB > 0 ? maxMempoolMB : 300))")

        let maxConnections = defaults.double(forKey: "max_connections")
        args.append("-maxconnections=\(Int(maxConnections > 0 ? maxConnections : 125))")

        // UserDefaults.bool returns false for unset keys; explicitly check
        // for the key's presence so the default (listen=true) is respected.
        if let listenValue = defaults.object(forKey: "listen_enabled") as? Bool, !listenValue {
            args.append("-listen=0")
        }

        let rpcAuth = defaults.string(forKey: "rpc_auth") ?? ""
        if !rpcAuth.isEmpty {
            args.append("-rpcauth=\(rpcAuth)")
        }

        return args
    }
}
