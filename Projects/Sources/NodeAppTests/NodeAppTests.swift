//
//  NodeAppTests.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
import Foundation
@testable import NodeApp

// MARK: - NodeState Tests

@Suite("NodeState")
struct NodeStateTests {

    @Test("Raw values match expected display strings")
    func rawValues() {
        #expect(NodeState.stopped.rawValue == "Stopped")
        #expect(NodeState.starting.rawValue == "Starting")
        #expect(NodeState.running.rawValue == "Running")
        #expect(NodeState.stopping.rawValue == "Stopping")
    }

    @Test("NodeState conforms to Sendable")
    func sendableConformance() {
        // Compile-time proof: assigning to a Sendable-typed variable succeeds.
        let state: any Sendable = NodeState.running
        #expect(state is NodeState)
    }
}

// MARK: - BitcoinNetwork Tests

@Suite("BitcoinNetwork")
struct BitcoinNetworkTests {

    @Test("Mainnet has no CLI argument")
    func mainnetNoArgument() {
        #expect(BitcoinNetwork.mainnet.argument == nil)
    }

    @Test("Testnet returns -testnet")
    func testnetArgument() {
        #expect(BitcoinNetwork.testnet.argument == "-testnet")
    }

    @Test("Signet returns -signet")
    func signetArgument() {
        #expect(BitcoinNetwork.signet.argument == "-signet")
    }

    @Test("Regtest returns -regtest")
    func regtestArgument() {
        #expect(BitcoinNetwork.regtest.argument == "-regtest")
    }
}

// MARK: - DaemonConfig.buildArguments() Tests

@Suite("buildArguments", .serialized)
struct BuildArgumentsTests {

    /// Reset all configuration keys to nil before each test so tests are isolated.
    private func resetDefaults() {
        let keys = [
            "bitcoin_network", "node_type", "prune_size_mb",
            "tor_enabled", "private_broadcast_enabled",
            "max_mempool_mb", "max_connections",
            "listen_enabled", "rpc_auth"
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: Fixed Arguments

    @Test("Always includes server and RPC binding arguments")
    func fixedArguments() {
        resetDefaults()
        let args = DaemonConfig.buildArguments()
        #expect(args.contains("-server=1"))
        #expect(args.contains("-rpcbind=127.0.0.1"))
        #expect(args.contains("-rpcallowip=127.0.0.1"))
        #expect(args.contains("-rpcport=8332"))
        #expect(args.contains(where: { $0.hasPrefix("-rpccookiefile=") }))
    }

    // MARK: Network

    @Test("Defaults to mainnet (no network argument)")
    func defaultMainnet() {
        resetDefaults()
        let args = DaemonConfig.buildArguments()
        #expect(!args.contains("-testnet"))
        #expect(!args.contains("-signet"))
        #expect(!args.contains("-regtest"))
    }

    @Test("Testnet adds -testnet argument")
    func testnet() {
        resetDefaults()
        UserDefaults.standard.set("Testnet", forKey: "bitcoin_network")
        let args = DaemonConfig.buildArguments()
        #expect(args.contains("-testnet"))
    }

    @Test("Signet adds -signet argument")
    func signet() {
        resetDefaults()
        UserDefaults.standard.set("Signet", forKey: "bitcoin_network")
        let args = DaemonConfig.buildArguments()
        #expect(args.contains("-signet"))
    }

    @Test("Regtest adds -regtest argument")
    func regtest() {
        resetDefaults()
        UserDefaults.standard.set("Regtest", forKey: "bitcoin_network")
        let args = DaemonConfig.buildArguments()
        #expect(args.contains("-regtest"))
    }

    // MARK: Node Type

    @Test("Default pruned node uses 550 MB prune size")
    func defaultPruned() {
        resetDefaults()
        let args = DaemonConfig.buildArguments()
        #expect(args.contains("-prune=550"))
    }

    @Test("Custom prune size is reflected")
    func customPruneSize() {
        resetDefaults()
        UserDefaults.standard.set("Pruned", forKey: "node_type")
        UserDefaults.standard.set(1000.0, forKey: "prune_size_mb")
        let args = DaemonConfig.buildArguments()
        #expect(args.contains("-prune=1000"))
    }

    @Test("Archival node adds no prune or filter arguments")
    func archival() {
        resetDefaults()
        UserDefaults.standard.set("Archival", forKey: "node_type")
        let args = DaemonConfig.buildArguments()
        #expect(!args.contains(where: { $0.hasPrefix("-prune=") }))
        #expect(!args.contains("-blockfilterindex=1"))
    }

    @Test("Compact filters node adds blockfilterindex and peerblockfilters")
    func compactFilters() {
        resetDefaults()
        UserDefaults.standard.set("Compact Block Filters", forKey: "node_type")
        let args = DaemonConfig.buildArguments()
        #expect(args.contains("-blockfilterindex=1"))
        #expect(args.contains("-peerblockfilters=1"))
        #expect(!args.contains(where: { $0.hasPrefix("-prune=") }))
    }

    // MARK: Privacy

    @Test("Tor disabled by default")
    func torDefault() {
        resetDefaults()
        let args = DaemonConfig.buildArguments()
        #expect(!args.contains(where: { $0.hasPrefix("-proxy=") }))
    }

    @Test("Tor enabled with proxy adds dynamic proxy argument")
    func torEnabledWithProxy() {
        resetDefaults()
        UserDefaults.standard.set(true, forKey: "tor_enabled")
        let args = DaemonConfig.buildArguments(torProxy: "127.0.0.1:43210")
        #expect(args.contains("-proxy=127.0.0.1:43210"))
    }

    @Test("Tor enabled without proxy omits proxy argument")
    func torEnabledNoProxy() {
        resetDefaults()
        UserDefaults.standard.set(true, forKey: "tor_enabled")
        let args = DaemonConfig.buildArguments()
        #expect(!args.contains(where: { $0.hasPrefix("-proxy=") }))
    }

    @Test("Tor disabled ignores torProxy parameter")
    func torDisabledIgnoresProxy() {
        resetDefaults()
        let args = DaemonConfig.buildArguments(torProxy: "127.0.0.1:9999")
        #expect(!args.contains(where: { $0.hasPrefix("-proxy=") }))
    }

    @Test("Private broadcast disabled by default")
    func privateBroadcastDefault() {
        resetDefaults()
        let args = DaemonConfig.buildArguments()
        #expect(!args.contains(where: { $0.hasPrefix("-privatebroadcast=") }))
    }

    @Test("Private broadcast enabled with live Tor adds -privatebroadcast")
    func privateBroadcastEnabled() {
        resetDefaults()
        UserDefaults.standard.set(true, forKey: "tor_enabled")
        UserDefaults.standard.set(true, forKey: "private_broadcast_enabled")
        let args = DaemonConfig.buildArguments(torProxy: "127.0.0.1:9050")
        #expect(args.contains("-privatebroadcast=1"))
    }

    // New defensive-gate tests — ensure `-privatebroadcast` never slips through
    // when Tor is not actually delivering a proxy.

    @Test("Private broadcast omitted when tor_enabled is false even if pref set")
    func privateBroadcastRequiresTor() {
        resetDefaults()
        UserDefaults.standard.set(false, forKey: "tor_enabled")
        UserDefaults.standard.set(true, forKey: "private_broadcast_enabled")
        let args = DaemonConfig.buildArguments(torProxy: "127.0.0.1:9050")
        #expect(!args.contains(where: { $0.hasPrefix("-privatebroadcast") }))
    }

    @Test("Private broadcast omitted when torProxy is nil (Tor not ready)")
    func privateBroadcastRequiresLiveProxy() {
        resetDefaults()
        UserDefaults.standard.set(true, forKey: "tor_enabled")
        UserDefaults.standard.set(true, forKey: "private_broadcast_enabled")
        let args = DaemonConfig.buildArguments(torProxy: nil)
        #expect(!args.contains(where: { $0.hasPrefix("-privatebroadcast") }))
    }

    @Test("tor_enabled with nil torProxy omits -proxy= (defensive)")
    func noProxyArgWhenTorNotReady() {
        resetDefaults()
        UserDefaults.standard.set(true, forKey: "tor_enabled")
        let args = DaemonConfig.buildArguments(torProxy: nil)
        #expect(!args.contains(where: { $0.hasPrefix("-proxy=") }))
    }

    // MARK: Resource Limits

    @Test("Default mempool size is 300 MB")
    func defaultMempool() {
        resetDefaults()
        let args = DaemonConfig.buildArguments()
        #expect(args.contains("-maxmempool=300"))
    }

    @Test("Custom mempool size is reflected")
    func customMempool() {
        resetDefaults()
        UserDefaults.standard.set(500.0, forKey: "max_mempool_mb")
        let args = DaemonConfig.buildArguments()
        #expect(args.contains("-maxmempool=500"))
    }

    @Test("Default max connections is 125")
    func defaultConnections() {
        resetDefaults()
        let args = DaemonConfig.buildArguments()
        #expect(args.contains("-maxconnections=125"))
    }

    @Test("Custom max connections is reflected")
    func customConnections() {
        resetDefaults()
        UserDefaults.standard.set(50.0, forKey: "max_connections")
        let args = DaemonConfig.buildArguments()
        #expect(args.contains("-maxconnections=50"))
    }

    // MARK: Listen

    @Test("Listen enabled by default (no -listen=0)")
    func listenDefaultEnabled() {
        resetDefaults()
        let args = DaemonConfig.buildArguments()
        #expect(!args.contains("-listen=0"))
    }

    @Test("Listen explicitly disabled adds -listen=0")
    func listenDisabled() {
        resetDefaults()
        UserDefaults.standard.set(false, forKey: "listen_enabled")
        let args = DaemonConfig.buildArguments()
        #expect(args.contains("-listen=0"))
    }

    @Test("Listen explicitly enabled does not add -listen=0")
    func listenExplicitlyEnabled() {
        resetDefaults()
        UserDefaults.standard.set(true, forKey: "listen_enabled")
        let args = DaemonConfig.buildArguments()
        #expect(!args.contains("-listen=0"))
    }

    // MARK: User RPC Auth

    @Test("No rpcauth when user rpc_auth is empty (cookie auth only)")
    func noRpcAuthByDefault() {
        resetDefaults()
        let args = DaemonConfig.buildArguments()
        let rpcAuthArgs = args.filter { $0.hasPrefix("-rpcauth=") }
        #expect(rpcAuthArgs.count == 0)
    }

    @Test("User rpc_auth adds -rpcauth argument")
    func userRpcAuth() {
        resetDefaults()
        UserDefaults.standard.set("user:salt\(String("$"))hash", forKey: "rpc_auth")
        let args = DaemonConfig.buildArguments()
        let rpcAuthArgs = args.filter { $0.hasPrefix("-rpcauth=") }
        #expect(rpcAuthArgs.count == 1)
    }
}

// MARK: - RPCCommand IBD Flag Tests

@Suite("RPCCommand IBD Flag")
struct RPCCommandIBDFlagTests {

    @Test("isHeavyDuringIBD defaults to false")
    func defaultIsFalse() {
        let cmd = RPCCommand(
            id: "test", name: "test", methodName: "test",
            description: "test", category: .control
        )
        #expect(cmd.isHeavyDuringIBD == false)
    }

    @Test("getchaintips is flagged as heavy during IBD")
    func getchaintipsFlagged() {
        let cmd = RPCCommand.parameterFreeCommands.first { $0.id == "getchaintips" }
        #expect(cmd != nil)
        #expect(cmd!.isHeavyDuringIBD == true)
    }

    @Test("getmininginfo is flagged as heavy during IBD")
    func getmininginfoFlagged() {
        let cmd = RPCCommand.parameterFreeCommands.first { $0.id == "getmininginfo" }
        #expect(cmd != nil)
        #expect(cmd!.isHeavyDuringIBD == true)
    }

    @Test("Most commands are not flagged as heavy during IBD")
    func mostCommandsNotFlagged() {
        let heavyCount = RPCCommand.parameterFreeCommands.filter(\.isHeavyDuringIBD).count
        #expect(heavyCount >= 1, "At least getchaintips should be flagged")
        #expect(heavyCount < RPCCommand.parameterFreeCommands.count, "Not all commands should be flagged")
    }
}

// MARK: - CommandsViewModel Pure Logic Tests

@Suite("CommandsViewModel Logic")
@MainActor
struct CommandsViewModelLogicTests {

    @Test("hasActiveExecutions is false initially")
    func initialState() {
        let vm = CommandsViewModel()
        #expect(!vm.hasActiveExecutions)
    }

    @Test("filteredCommands returns all commands when search is empty")
    func noFilter() {
        let vm = CommandsViewModel()
        vm.searchText = ""
        #expect(vm.filteredCommands.count == vm.commands.count)
    }

    @Test("filteredCommands filters by command name")
    func filterByName() {
        let vm = CommandsViewModel()
        vm.searchText = "getblockcount"
        let matches = vm.filteredCommands
        #expect(matches.allSatisfy { $0.name.localizedCaseInsensitiveContains("getblockcount") || $0.description.localizedCaseInsensitiveContains("getblockcount") || $0.category.rawValue.localizedCaseInsensitiveContains("getblockcount") })
    }

    @Test("filteredCommands returns empty for nonsense search")
    func noMatches() {
        let vm = CommandsViewModel()
        vm.searchText = "zzzznonexistentzzzz"
        #expect(vm.filteredCommands.isEmpty)
    }

    @Test("commandsByCategory groups correctly")
    func grouping() {
        let vm = CommandsViewModel()
        vm.searchText = ""
        let categories = vm.commandsByCategory
        // Every section has at least one command
        for section in categories {
            #expect(!section.commands.isEmpty)
            // All commands in a section belong to that category
            #expect(section.commands.allSatisfy { $0.category == section.category })
        }
    }

    @Test("commandsByCategory follows RPCCategory.allCases order")
    func categoryOrder() {
        let vm = CommandsViewModel()
        vm.searchText = ""
        let sectionCategories = vm.commandsByCategory.map(\.category)
        let allCases = RPCCategory.allCases
        // sectionCategories should be a subsequence of allCases (same relative order)
        var caseIndex = allCases.startIndex
        for cat in sectionCategories {
            while caseIndex < allCases.endIndex, allCases[caseIndex] != cat {
                caseIndex = allCases.index(after: caseIndex)
            }
            #expect(caseIndex < allCases.endIndex, "Category \(cat) out of order")
            caseIndex = allCases.index(after: caseIndex)
        }
    }

    @Test("response and error are nil initially for any command")
    func initialResponseAndError() {
        let vm = CommandsViewModel()
        guard let command = vm.commands.first else {
            Issue.record("No commands available")
            return
        }
        #expect(vm.response(for: command) == nil)
        #expect(vm.error(for: command) == nil)
    }
}
