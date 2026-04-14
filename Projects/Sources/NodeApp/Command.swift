//
//  Command.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

enum RPCCategory: String, CaseIterable, Identifiable {
    case blockchain = "Blockchain"
    case network = "Network"
    case mining = "Mining"
    case control = "Control"
    case util = "Util"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .blockchain: "cube.transparent"
        case .network: "network"
        case .mining: "hammer"
        case .control: "gearshape"
        case .util: "wrench"
        }
    }
}

struct RPCCommand: Identifiable, Hashable {
    let id: String
    let name: String
    let methodName: String
    let description: String
    let category: RPCCategory

    static let parameterFreeCommands: [RPCCommand] = [
        // MARK: - Blockchain
        RPCCommand(
            id: "getbestblockhash", name: "getBestBlockHash", methodName: "getbestblockhash",
            description: "Returns the hash of the best (tip) block in the most-work fully-validated chain.",
            category: .blockchain
        ),
        RPCCommand(
            id: "getblockcount", name: "getBlockCount", methodName: "getblockcount",
            description: "Returns the height of the most-work fully-validated chain.",
            category: .blockchain
        ),
        RPCCommand(
            id: "getblockchaininfo", name: "getBlockchainInfo", methodName: "getblockchaininfo",
            description: "Returns an object containing various state info regarding blockchain processing.",
            category: .blockchain
        ),
        RPCCommand(
            id: "getchaintips", name: "getChainTips", methodName: "getchaintips",
            description: "Return information about all known tips in the block tree.",
            category: .blockchain
        ),
        RPCCommand(
            id: "getdifficulty", name: "getDifficulty", methodName: "getdifficulty",
            description: "Returns the proof-of-work difficulty as a multiple of the minimum difficulty.",
            category: .blockchain
        ),
        RPCCommand(
            id: "getmempoolinfo", name: "getMempoolInfo", methodName: "getmempoolinfo",
            description: "Returns details on the active state of the TX memory pool.",
            category: .blockchain
        ),
        RPCCommand(
            id: "getrawmempool", name: "getRawMempool", methodName: "getrawmempool",
            description: "Returns all transaction ids in memory pool.",
            category: .blockchain
        ),
        RPCCommand(
            id: "getchainstates", name: "getChainStates", methodName: "getchainstates",
            description: "Returns information about chainstates.",
            category: .blockchain
        ),

        // MARK: - Network
        RPCCommand(
            id: "getnetworkinfo", name: "getNetworkInfo", methodName: "getnetworkinfo",
            description: "Returns an object containing various state info regarding P2P networking.",
            category: .network
        ),
        RPCCommand(
            id: "getpeerinfo", name: "getPeerInfo", methodName: "getpeerinfo",
            description: "Returns data about each connected network peer.",
            category: .network
        ),
        RPCCommand(
            id: "getconnectioncount", name: "getConnectionCount", methodName: "getconnectioncount",
            description: "Returns the number of connections to other nodes.",
            category: .network
        ),
        RPCCommand(
            id: "getnettotals", name: "getNetTotals", methodName: "getnettotals",
            description: "Returns information about network traffic, including bytes in, bytes out, and current time.",
            category: .network
        ),
        RPCCommand(
            id: "listbanned", name: "listBanned", methodName: "listbanned",
            description: "List all manually banned IPs/Subnets.",
            category: .network
        ),
        RPCCommand(
            id: "getzmqnotifications", name: "getZMQNotifications", methodName: "getzmqnotifications",
            description: "Returns information about the active ZeroMQ notifications.",
            category: .network
        ),
        RPCCommand(
            id: "getaddrmaninfo", name: "getAddrmanInfo", methodName: "getaddrmaninfo",
            description: "Provides information about the node's address manager.",
            category: .network
        ),

        // MARK: - Mining
        RPCCommand(
            id: "getmininginfo", name: "getMiningInfo", methodName: "getmininginfo",
            description: "Returns a json object containing mining-related information.",
            category: .mining
        ),
        RPCCommand(
            id: "getprioritisedtransactions", name: "getPrioritisedTransactions",
            methodName: "getprioritisedtransactions",
            description: "Returns a map of all user-created (see prioritisetransaction) fee deltas by txid.",
            category: .mining
        ),

        // MARK: - Control
        RPCCommand(
            id: "getmemoryinfo", name: "getMemoryInfo", methodName: "getmemoryinfo",
            description: "Returns an object containing information about memory usage.",
            category: .control
        ),
        RPCCommand(
            id: "getrpcinfo", name: "getRPCInfo", methodName: "getrpcinfo",
            description: "Returns details of the RPC server.",
            category: .control
        ),
        RPCCommand(
            id: "uptime", name: "uptime", methodName: "uptime",
            description: "Returns the total uptime of the server in seconds.",
            category: .control
        ),

        // MARK: - Util
        RPCCommand(
            id: "getindexinfo", name: "getIndexInfo", methodName: "getindexinfo",
            description: "Returns the status of one or all available indices currently running in the node.",
            category: .util
        ),
    ]
}
