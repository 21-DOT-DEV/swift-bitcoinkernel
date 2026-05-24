//
//  RPCClient+Network.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

// MARK: - Network RPCs
// https://developer.bitcoin.org/reference/rpc/#network-rpcs

extension RPCClient {

    /// Returns information about the node's connection to the network.
    public func getNetworkInfo() async throws -> NetworkInfo {
        try await send("getnetworkinfo")
    }

    /// Returns data about each connected network node.
    public func getPeerInfo() async throws -> [PeerInfo] {
        try await send("getpeerinfo")
    }

    /// Returns the number of connections to other nodes.
    public func getConnectionCount() async throws -> Int {
        try await send("getconnectioncount")
    }

    /// Returns network traffic statistics.
    public func getNetTotals() async throws -> NetTotals {
        try await send("getnettotals")
    }

    /// Returns known addresses from the node's address manager.
    ///
    /// - Parameter count: The maximum number of addresses to return (default 1).
    public func getNodeAddresses(count: Int = 1) async throws -> [NodeAddress] {
        try await send("getnodeaddresses", params: [.int(count)])
    }

    /// Returns information about the given added node.
    ///
    /// - Parameter node: Node address to get info about. If `nil`, returns all added nodes.
    public func getAddedNodeInfo(node: String? = nil) async throws -> [AddedNodeInfo] {
        var params: [RPCParam] = []
        if let node { params.append(.string(node)) }
        return try await send("getaddednodeinfo", params: params)
    }

    /// Attempts to add or remove a node from the addnode list.
    ///
    /// - Parameters:
    ///   - address: The node address (host:port).
    ///   - command: "add", "remove", or "onetry".
    public func addNode(address: String, command: String) async throws {
        try await sendVoid("addnode", params: [.string(address), .string(command)])
    }

    /// Disconnects a node by address or node ID.
    ///
    /// - Parameters:
    ///   - address: The IP address/port of the node (optional).
    ///   - nodeId: The node ID (optional). Provide exactly one of `address` or `nodeId`.
    public func disconnectNode(address: String? = nil, nodeId: Int? = nil) async throws {
        var params: [RPCParam] = []
        if let address {
            params.append(.string(address))
        } else if let nodeId {
            params.append(.string(""))
            params.append(.int(nodeId))
        }
        try await sendVoid("disconnectnode", params: params)
    }

    /// Clears all banned IPs.
    public func clearBanned() async throws {
        try await sendVoid("clearbanned")
    }

    /// Returns all banned IPs/Subnets.
    public func listBanned() async throws -> [BannedInfo] {
        try await send("listbanned")
    }

    /// Requests a ping to be sent to all connected nodes.
    public func ping() async throws {
        try await sendVoid("ping")
    }

    /// Adds or removes an IP/Subnet from the banned list.
    ///
    /// - Parameters:
    ///   - subnet: The IP/Subnet with optional netmask.
    ///   - command: "add" or "remove".
    ///   - banTime: Time in seconds to ban (0 = default 24h). Only for "add".
    ///   - absolute: If true, `banTime` is an absolute UNIX timestamp.
    public func setBan(subnet: String, command: String, banTime: Int = 0, absolute: Bool = false) async throws {
        try await sendVoid("setban", params: [.string(subnet), .string(command), .int(banTime), .bool(absolute)])
    }

    /// Enables or disables all P2P network activity.
    ///
    /// - Returns: The new network active state.
    public func setNetworkActive(_ state: Bool) async throws -> Bool {
        try await send("setnetworkactive", params: [.bool(state)])
    }

    /// Returns information about all active ZMQ notification endpoints (v17+).
    public func getZMQNotifications() async throws -> [ZMQNotification] {
        try await send("getzmqnotifications")
    }

    /// Adds a peer address to the address manager (testing, v22+).
    ///
    /// - Parameters:
    ///   - address: The IP address of the peer.
    ///   - port: The port of the peer.
    ///   - tried: Whether to add to the tried table (default false = new table).
    /// - Returns: Raw JSON with success status.
    public func addPeerAddress(address: String, port: Int, tried: Bool = false) async throws -> Data {
        try await call("addpeeraddress", params: [.string(address), .int(port), .bool(tried)])
    }

    /// Opens a connection to a node (testing, v22+).
    ///
    /// - Parameters:
    ///   - address: The IP address and port of the node.
    ///   - connectionType: "outbound-full-relay", "block-relay-only", "addr-fetch", or "feeler".
    /// - Returns: Raw JSON with connection info.
    public func addConnection(address: String, connectionType: String) async throws -> Data {
        try await call("addconnection", params: [.string(address), .string(connectionType)])
    }

    /// Sends a p2p message to a connected peer (testing, v25+).
    ///
    /// - Parameters:
    ///   - peerId: The peer id.
    ///   - msgType: The p2p message type (e.g., "addr", "getdata").
    ///   - msg: The hex-encoded message data.
    public func sendMsgToPeer(peerId: Int, msgType: String, msg: String) async throws {
        try await sendVoid("sendmsgtopeer", params: [.int(peerId), .string(msgType), .string(msg)])
    }

    /// Returns information about the node's address manager (v26+).
    public func getAddrmanInfo() async throws -> Data {
        try await call("getaddrmaninfo")
    }

    /// Returns the raw address manager table contents (v26+, EXPERIMENTAL).
    public func getRawAddrman() async throws -> Data {
        try await call("getrawaddrman")
    }
}
