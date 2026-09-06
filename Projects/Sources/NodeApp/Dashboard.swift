//
//  Dashboard.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import Observation
import Bitcoin

// MARK: - Data source (dependency-injection seam)

/// The RPC surface the operator dashboard polls. `RPCClient` conforms for
/// production; tests inject a fixture conformer so the view-model's mapping
/// logic can be exercised without a live daemon.
protocol DashboardDataSource: Sendable {
    func blockchainInfo() async throws -> BlockchainInfo
    func peers() async throws -> [PeerInfo]
    func mempoolInfo() async throws -> MempoolInfo
    /// Summary connection counts. Deliberately not the full peer list, which
    /// returns an object per connected peer; only the count is needed and the
    /// summary is a handful of numbers.
    func networkInfo() async throws -> NetworkInfo
}

extension RPCClient: DashboardDataSource {
    func blockchainInfo() async throws -> BlockchainInfo { try await getBlockchainInfo() }
    func peers() async throws -> [PeerInfo] { try await getPeerInfo() }
    func mempoolInfo() async throws -> MempoolInfo { try await getMempoolInfo() }
    func networkInfo() async throws -> NetworkInfo { try await getNetworkInfo() }
}

// MARK: - Display summaries (pure value types, computed from RPC results)

struct ChainSummary: Equatable {
    let chain: String
    let height: Int
    let bestBlockHash: String
    let tipTime: Date

    init(_ info: BlockchainInfo) {
        chain = info.chain
        height = info.blocks
        bestBlockHash = info.bestblockhash
        tipTime = info.time.date
    }
}

struct SyncSummary: Equatable {
    let verificationProgress: Double   // 0...1
    let isInitialBlockDownload: Bool
    let blocks: Int
    let headers: Int

    /// Headers known but not yet downloaded as full blocks (the IBD gap).
    var headersAhead: Int { max(0, headers - blocks) }

    init(_ info: BlockchainInfo) {
        verificationProgress = info.verificationprogress
        isInitialBlockDownload = info.initialblockdownload
        blocks = info.blocks
        headers = info.headers
    }
}

struct PeerRow: Identifiable, Equatable {
    let id: Int
    let addr: String
    let subver: String
    let network: String
    let connectionType: String
    let transport: String
    let pingMilliseconds: Double?
    let inbound: Bool

    init(_ peer: PeerInfo) {
        id = peer.id
        addr = peer.addr
        subver = peer.subver
        network = peer.network ?? "unknown"
        connectionType = peer.connectionType ?? (peer.inbound ? "inbound" : "outbound")
        transport = peer.transportProtocolType ?? "v1"
        pingMilliseconds = peer.pingtime.map { $0 * 1000 }
        inbound = peer.inbound
    }
}

struct PeerSummary: Equatable {
    let total: Int
    let inbound: Int
    let outbound: Int
    let onion: Int
    let clearnet: Int
    let rows: [PeerRow]

    init(_ peers: [PeerInfo]) {
        total = peers.count
        inbound = peers.filter { $0.inbound }.count
        outbound = total - inbound
        onion = peers.filter { $0.network == "onion" }.count
        clearnet = peers.filter { $0.network == "ipv4" || $0.network == "ipv6" }.count
        rows = peers.map(PeerRow.init)
    }
}

struct MempoolSummary: Equatable {
    let count: Int
    let vsizeBytes: Int
    let usageBytes: Int
    let maxBytes: Int
    let minFeeBTCPerKvB: Double

    /// Memory usage as a fraction of `-maxmempool` (0...1).
    var usageFraction: Double {
        maxBytes > 0 ? min(1, Double(usageBytes) / Double(maxBytes)) : 0
    }

    /// Minimum relay fee in sat/vB (the operator-facing unit).
    var minFeeSatPerVByte: Double { minFeeBTCPerKvB * 100_000 }

    init(_ info: MempoolInfo) {
        count = info.size
        vsizeBytes = info.bytes
        usageBytes = info.usage
        maxBytes = info.maxmempool
        minFeeBTCPerKvB = info.mempoolminfee
    }
}

struct StorageSummary: Equatable {
    let sizeOnDiskBytes: Int
    let pruned: Bool
    let pruneTargetBytes: Int?

    init(_ info: BlockchainInfo) {
        sizeOnDiskBytes = info.sizeOnDisk
        pruned = info.pruned
        pruneTargetBytes = info.pruneTargetSize
    }
}

// MARK: - View model

/// Polls the embedded daemon over the typed `RPCClient` and exposes the
/// operator surfaces a node runner expects. The poll cadence lives in
/// ``DashboardView``; this type owns the data source and the mapping.
@MainActor
@Observable
final class DashboardViewModel {
    private let source: DashboardDataSource

    private(set) var chain: ChainSummary?
    private(set) var sync: SyncSummary?
    private(set) var peers: PeerSummary?
    private(set) var mempool: MempoolSummary?
    private(set) var storage: StorageSummary?
    private(set) var lastUpdated: Date?
    private(set) var lastError: String?

    init(source: DashboardDataSource) {
        self.source = source
    }

    /// Fetches all surfaces concurrently and updates the published summaries.
    /// On failure the previous values are kept and `lastError` is set, so a
    /// transient RPC error does not blank an established dashboard.
    func refresh() async {
        do {
            async let info = source.blockchainInfo()
            async let peerList = source.peers()
            async let pool = source.mempoolInfo()
            let (blockchain, connectedPeers, mempoolInfo) = try await (info, peerList, pool)

            chain = ChainSummary(blockchain)
            sync = SyncSummary(blockchain)
            peers = PeerSummary(connectedPeers)
            mempool = MempoolSummary(mempoolInfo)
            storage = StorageSummary(blockchain)
            lastUpdated = Date()
            lastError = nil
        } catch is CancellationError {
            // Poll loop cancelled (node stopped / app backgrounded); ignore.
        } catch {
            lastError = error.localizedDescription
        }
    }
}
