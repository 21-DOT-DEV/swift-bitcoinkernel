//
//  NodeAddress.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Known node address from `getnodeaddresses`.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct NodeAddress: Codable, Sendable, Equatable {
    /// The UNIX epoch time when the node was last seen.
    public let time: UnixTimestamp

    /// The services offered by the node.
    public let services: Int64

    /// The address of the node.
    public let address: String

    /// The port of the node.
    public let port: Int

    /// The network (ipv4, ipv6, onion, i2p, cjdns).
    public let network: String?
}
