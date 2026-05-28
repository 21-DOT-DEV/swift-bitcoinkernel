//
//  PeerInfo.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Per-peer information from `getpeerinfo`.
///
/// Many fields are optional across Bitcoin Core versions.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct PeerInfo: Codable, Sendable, Equatable {
    /// Peer index.
    public let id: Int
    /// The IP address and port of the peer (`host:port`).
    public let addr: String
    /// Bind address of the connection to the peer (`ip:port`).
    public let addrbind: String?
    /// Local address as reported by the peer (`ip:port`).
    public let addrlocal: String?
    /// Network type (`ipv4`, `ipv6`, `onion`, `i2p`, `cjdns`, or `not_publicly_routable`).
    public let network: String?
    /// Mapped AS (Autonomous System) number at the end of the BGP route to the peer, used for
    /// diversifying peer selection. Only present if the `-asmap` config option is set.
    public let mappedAs: Int?
    /// The services offered, as a hexadecimal string.
    public let services: String
    /// The services offered, in human-readable form.
    public let servicesnames: [String]?
    /// Whether we relay transactions to this peer.
    public let relaytxes: Bool
    /// Mempool sequence number of this peer's last INV.
    public let lastInvSequence: Int?
    /// How many transactions we have queued to announce to this peer.
    public let invToSend: Int?
    /// The time of the last send.
    public let lastsend: UnixTimestamp
    /// The time of the last receive.
    public let lastrecv: UnixTimestamp
    /// The time of the last valid transaction received from this peer.
    public let lastTransaction: UnixTimestamp?
    /// The time of the last block received from this peer.
    public let lastBlock: UnixTimestamp?
    /// The total bytes sent.
    public let bytessent: Int64
    /// The total bytes received.
    public let bytesrecv: Int64
    /// The time of the connection.
    public let conntime: UnixTimestamp
    /// The time offset in seconds.
    public let timeoffset: Int
    /// The last ping time in seconds, if any.
    public let pingtime: Double?
    /// The minimum observed ping time in seconds, if any.
    public let minping: Double?
    /// The duration in seconds of an outstanding ping (if non-zero).
    public let pingwait: Double?
    /// The peer protocol version, such as `70016`.
    public let version: Int
    /// The peer's user agent string.
    public let subver: String
    /// Whether this is an inbound (`true`) or outbound (`false`) connection.
    public let inbound: Bool
    /// Whether we selected this peer as a BIP 152 compact blocks high-bandwidth peer.
    public let bip152HbTo: Bool?
    /// Whether this peer selected us as a BIP 152 compact blocks high-bandwidth peer.
    public let bip152HbFrom: Bool?
    /// The starting height (block) of the peer. Deprecated; only returned if
    /// `-deprecatedrpc=startingheight` is passed.
    public let startingheight: Int?
    /// The current height of header pre-synchronization with this peer, or `-1` if no
    /// low-work sync is in progress.
    public let presyncedHeaders: Int?
    /// The last header we have in common with this peer.
    public let syncedHeaders: Int
    /// The last block we have in common with this peer.
    public let syncedBlocks: Int
    /// The heights of blocks we're currently asking from this peer.
    public let inflight: [Int]?
    /// Whether we participate in address relay with this peer.
    public let addrRelayEnabled: Bool?
    /// The total number of addresses processed, excluding those dropped due to rate limiting.
    public let addrProcessed: Int64?
    /// The total number of addresses dropped due to rate limiting.
    public let addrRateLimited: Int64?
    /// Any special permissions that have been granted to this peer.
    public let permissions: [String]?
    /// The minimum fee rate for transactions this peer accepts.
    public let minfeefilter: Double?
    /// The total bytes sent aggregated by message type. When a message type is not listed,
    /// the bytes sent are 0.
    public let bytessentPerMsg: [String: Int64]?
    /// The total bytes received aggregated by message type. When a message type is not listed,
    /// the bytes received are 0. Unknown message types are listed under `"other"`.
    public let bytesrecvPerMsg: [String: Int64]?
    /// Type of connection: `outbound-full-relay`, `block-relay-only`, `inbound`, `manual`,
    /// `addr-fetch`, or `feeler`.
    public let connectionType: String?
    /// Type of transport protocol: `detecting`, `v1`, or `v2`.
    public let transportProtocolType: String?
    /// The session ID for this connection, or empty if there is none (`v2` transport only).
    public let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case id, addr, addrbind, addrlocal, network, services, servicesnames
        case mappedAs = "mapped_as"
        case lastInvSequence = "last_inv_sequence"
        case invToSend = "inv_to_send"
        case relaytxes, lastsend, lastrecv, bytessent, bytesrecv, conntime
        case timeoffset, pingtime, minping, pingwait, version, subver
        case inbound, startingheight, inflight
        case permissions, minfeefilter
        case lastTransaction = "last_transaction"
        case lastBlock = "last_block"
        case bip152HbTo = "bip152_hb_to"
        case bip152HbFrom = "bip152_hb_from"
        case presyncedHeaders = "presynced_headers"
        case syncedHeaders = "synced_headers"
        case syncedBlocks = "synced_blocks"
        case addrRelayEnabled = "addr_relay_enabled"
        case addrProcessed = "addr_processed"
        case addrRateLimited = "addr_rate_limited"
        case bytessentPerMsg = "bytessent_per_msg"
        case bytesrecvPerMsg = "bytesrecv_per_msg"
        case connectionType = "connection_type"
        case transportProtocolType = "transport_protocol_type"
        case sessionId = "session_id"
    }
}
