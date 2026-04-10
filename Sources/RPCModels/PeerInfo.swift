//
//  PeerInfo.swift
//  21-DOT-DEV/RPCModels
//
//  Copyright (c) 2024 Timechain Software Initiative
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
    public let id: Int
    public let addr: String
    public let addrbind: String?
    public let addrlocal: String?
    public let network: String?
    public let mappedAs: Int?
    public let services: String
    public let servicesnames: [String]?
    public let relaytxes: Bool
    public let lastInvSequence: Int?
    public let invToSend: Int?
    public let lastsend: UnixTimestamp
    public let lastrecv: UnixTimestamp
    public let lastTransaction: UnixTimestamp?
    public let lastBlock: UnixTimestamp?
    public let bytessent: Int64
    public let bytesrecv: Int64
    public let conntime: UnixTimestamp
    public let timeoffset: Int
    public let pingtime: Double?
    public let minping: Double?
    public let pingwait: Double?
    public let version: Int
    public let subver: String
    public let inbound: Bool
    public let bip152HbTo: Bool?
    public let bip152HbFrom: Bool?
    public let startingheight: Int?
    public let presyncedHeaders: Int?
    public let syncedHeaders: Int
    public let syncedBlocks: Int
    public let inflight: [Int]?
    public let addrRelayEnabled: Bool?
    public let addrProcessed: Int64?
    public let addrRateLimited: Int64?
    public let permissions: [String]?
    public let minfeefilter: Double?
    public let bytessentPerMsg: [String: Int64]?
    public let bytesrecvPerMsg: [String: Int64]?
    public let connectionType: String?
    public let transportProtocolType: String?
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
