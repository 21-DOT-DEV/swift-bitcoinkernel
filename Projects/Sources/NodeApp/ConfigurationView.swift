//
//  ConfigurationView.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2022-present Timechain Software Initiative, Inc.
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
    var torViewModel: TorViewModel

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

    // Display
    @AppStorage("keep_screen_awake") private var keepScreenAwake = false

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

    /// The Tor session currently active in the UI (or `nil` if Tor is off).
    private var currentTorSession: UUID? {
        torEnabled ? torViewModel.sessionID : nil
    }

    /// `true` when the live Tor session differs from the one the running
    /// daemon was launched against. Catches both Tor restart (new session
    /// UUID → dead port) and user toggling Tor on/off while node is up.
    private var torConfigurationDrift: Bool {
        nodeViewModel.isRunning && currentTorSession != nodeViewModel.launchedWithTorSession
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
                        .onChange(of: torEnabled) { _, enabled in
                            if enabled {
                                torViewModel.start()
                            } else {
                                torViewModel.stop()
                                // Clear persisted private-broadcast preference so a
                                // later daemon launch without Tor can't silently emit
                                // -privatebroadcast.
                                privateBroadcastEnabled = false
                            }
                        }

                    TorStatusView(viewModel: torViewModel)

                    Toggle("Private Broadcast", isOn: $privateBroadcastEnabled)
                        .disabled(!torEnabled || !torViewModel.isReady)

                    if torConfigurationDrift {
                        Label {
                            Text("Tor session changed — restart the node for connections to work.")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        .font(.caption)
                    }
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
                Section {
                    Toggle("Keep Screen Awake", isOn: $keepScreenAwake)
                } header: {
                    Label("Display", systemImage: "sun.max")
                } footer: {
                    Text("Stops the screen from locking while the app is open. Uses more battery.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Configuration")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NodeToolbarMenu(
                        nodeViewModel: nodeViewModel,
                        torViewModel: torViewModel,
                        buildArguments: { DaemonConfig.buildArguments(torProxy: torViewModel.proxyAddress) }
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                if nodeViewModel.isRunning {
                    VStack(spacing: 4) {
                        Button {
                            let socksPort = torEnabled
                                ? torViewModel.socksEndpoint.map { UInt16(clamping: $0.port) } : nil
                            Task {
                                await nodeViewModel.applyAndRestart(
                                    arguments: DaemonConfig.buildArguments(torProxy: torViewModel.proxyAddress),
                                    torSession: torEnabled ? torViewModel.sessionID : nil,
                                    torSocksPort: socksPort
                                )
                            }
                        } label: {
                            Label("Apply & Restart", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Text("Restarts the node in place to apply configuration changes.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
            }
        }
    }

}
