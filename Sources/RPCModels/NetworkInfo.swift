//
//  NetworkInfo.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
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
    public let version: Int
    public let subversion: String
    public let protocolversion: Int
    public let localservices: String
    public let localservicesnames: [String]
    public let localrelay: Bool
    public let timeoffset: Int
    public let connections: Int
    public let connectionsIn: Int
    public let connectionsOut: Int
    public let networkactive: Bool
    public let networks: [NetworkInfoNetwork]
    public let relayfee: Double
    public let incrementalfee: Double
    public let localaddresses: [LocalAddress]
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
    public let name: String
    public let limited: Bool
    public let reachable: Bool
    public let proxy: String
    public let proxyRandomizeCredentials: Bool

    enum CodingKeys: String, CodingKey {
        case name, limited, reachable, proxy
        case proxyRandomizeCredentials = "proxy_randomize_credentials"
    }
}

/// Local address entry within `getnetworkinfo`.
public struct LocalAddress: Codable, Sendable, Equatable {
    public let address: String
    public let port: Int
    public let score: Int
}
