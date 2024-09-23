import Foundation

public struct PeerInfo: Codable {
    public let id: Int
    public let addr: String
    public let addrbind: String
    public let addrlocal: String?
    public let network: String
    public let mappedAS: Int?
    public let services: String
    public let servicesnames: [String]
    public let relaytxes: Bool
    public let lastsend: Int64
    public let lastrecv: Int64
    public let lastTransaction: Int64
    public let lastBlock: Int64
    public let bytessent: Int64
    public let bytesrecv: Int64
    public let conntime: Int64
    public let timeoffset: Int
    public let pingtime: Double?
    public let minping: Double?
    public let pingwait: Double?
    public let version: Int
    public let subver: String
    public let inbound: Bool
    public let addnode: Bool?
    public let connectionType: String
    public let startingheight: Int
    public let banscore: Int?
    public let syncedHeaders: Int
    public let syncedBlocks: Int
    public let inflight: [Int]
    public let whitelisted: Bool?
    public let permissions: [String]
    public let minfeefilter: Double
    public let bytesSentPerMsg: [String: Int64]
    public let bytesRecvPerMsg: [String: Int64]
    
    enum CodingKeys: String, CodingKey {
        case id, addr, addrbind, addrlocal, network, services, servicesnames, relaytxes, lastsend, lastrecv, bytessent, bytesrecv, conntime, timeoffset, pingtime, minping, pingwait, version, subver, inbound, addnode, startingheight, banscore, inflight, whitelisted, permissions, minfeefilter
        case mappedAS = "mapped_as"
        case lastTransaction = "last_transaction"
        case lastBlock = "last_block"
        case connectionType = "connection_type"
        case syncedHeaders = "synced_headers"
        case syncedBlocks = "synced_blocks"
        case bytesSentPerMsg = "bytessent_per_msg"
        case bytesRecvPerMsg = "bytesrecv_per_msg"
    }
}