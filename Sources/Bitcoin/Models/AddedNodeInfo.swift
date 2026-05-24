//
//  AddedNodeInfo.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Information about a manually added node from `getaddednodeinfo`.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct AddedNodeInfo: Codable, Sendable, Equatable {
    /// The node IP address or name.
    public let addednode: String

    /// Whether the node is currently connected.
    public let connected: Bool

    /// Connection details.
    public let addresses: [AddedNodeAddress]
}

/// Address details for an added node.
public struct AddedNodeAddress: Codable, Sendable, Equatable {
    /// The bitcoin server IP and port.
    public let address: String

    /// "inbound" or "outbound" connection direction.
    public let connected: String
}
