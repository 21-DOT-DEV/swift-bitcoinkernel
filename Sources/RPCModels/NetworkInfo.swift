//
//  NetworkInfo.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Network information from `getnetworkinfo`.
///
/// Fee rate fields (`relayfee`, `incrementalfee`) are in **BTC/kvB**.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct NetworkInfo: Codable, Sendable, Equatable {
    /// The server version.
    public let version: Int
    /// The server subversion string.
    public let subversion: String
    /// The protocol version.
    public let protocolversion: Int
    /// The services we offer to the network, as a hexadecimal string.
    public let localservices: String
    /// The services we offer to the network, in human-readable form.
    public let localservicesnames: [String]
    /// Whether transaction relay is requested from peers.
    public let localrelay: Bool
    /// The time offset in seconds.
    public let timeoffset: Int
    /// The total number of connections.
    public let connections: Int
    /// The number of inbound connections.
    public let connectionsIn: Int
    /// The number of outbound connections.
    public let connectionsOut: Int
    /// Whether p2p networking is enabled.
    public let networkactive: Bool
    /// Information per network.
    public let networks: [NetworkInfoNetwork]
    /// Minimum relay fee rate for transactions in BTC/kvB.
    public let relayfee: Double
    /// Minimum fee rate increment for mempool limiting or replacement in BTC/kvB.
    public let incrementalfee: Double
    /// List of local addresses.
    public let localaddresses: [LocalAddress]
    /// Any network and blockchain warnings.
    public let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case version, subversion, protocolversion, localservices
        case localservicesnames, localrelay, timeoffset, connections
        case networkactive, networks, relayfee, incrementalfee
        case localaddresses, warnings
        case connectionsIn = "connections_in"
        case connectionsOut = "connections_out"
    }
}

/// Per-network details within `getnetworkinfo`.
public struct NetworkInfoNetwork: Codable, Sendable, Equatable {
    /// Network name (ipv4, ipv6, onion, i2p, cjdns).
    public let name: String
    /// Whether the network is limited using `-onlynet`.
    public let limited: Bool
    /// Whether the network is reachable.
    public let reachable: Bool
    /// The proxy that is used for this network, or empty if none.
    public let proxy: String
    /// Whether randomized credentials are used for the proxy.
    public let proxyRandomizeCredentials: Bool

    enum CodingKeys: String, CodingKey {
        case name, limited, reachable, proxy
        case proxyRandomizeCredentials = "proxy_randomize_credentials"
    }
}

/// Local address entry within `getnetworkinfo`.
public struct LocalAddress: Codable, Sendable, Equatable {
    /// Network address.
    public let address: String
    /// Network port.
    public let port: Int
    /// Relative score.
    public let score: Int
}
