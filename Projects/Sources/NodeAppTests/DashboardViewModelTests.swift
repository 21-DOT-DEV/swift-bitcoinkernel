//
//  DashboardViewModelTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
import Foundation
import Bitcoin
@testable import NodeApp

@Suite("Dashboard View Model")
@MainActor
struct DashboardViewModelTests {

    /// Static `DashboardDataSource` returning canned RPC results — the
    /// dependency-injection seam, so the mapping runs without a live daemon.
    struct FixtureSource: DashboardDataSource {
        let info: BlockchainInfo
        let peerList: [PeerInfo]
        let pool: MempoolInfo
        func blockchainInfo() async throws -> BlockchainInfo { info }
        func peers() async throws -> [PeerInfo] { peerList }
        func mempoolInfo() async throws -> MempoolInfo { pool }
        /// The dashboard does not read this; only the unattended action does. Kept
        /// unimplemented rather than faked so a future dashboard use fails loudly
        /// here instead of quietly reading a made-up connection count.
        func networkInfo() async throws -> NetworkInfo {
            throw CocoaError(.featureUnsupported)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private static func source(
        info: String = prunedJSON,
        peers: String = "[]",
        mempool: String = mempoolJSON
    ) throws -> FixtureSource {
        FixtureSource(
            info: try decode(BlockchainInfo.self, info),
            peerList: try decode([PeerInfo].self, peers),
            pool: try decode(MempoolInfo.self, mempool)
        )
    }

    @Test("maps a pruned mainnet tip into chain/sync/storage summaries")
    func prunedMainnet() async throws {
        let vm = DashboardViewModel(source: try Self.source())
        await vm.refresh()
        #expect(vm.chain?.chain == "main")
        #expect(vm.chain?.height == 876000)
        #expect(vm.storage?.pruned == true)
        #expect(vm.storage?.pruneTargetBytes == 1_073_741_824)
        #expect(vm.storage?.sizeOnDiskBytes == 12_345_678_901)
        #expect(vm.sync?.isInitialBlockDownload == false)
        #expect(vm.sync?.headersAhead == 0)
        #expect(vm.lastError == nil)
        #expect(vm.lastUpdated != nil)
    }

    @Test("splits peers by direction and network")
    func peerSplit() async throws {
        let vm = DashboardViewModel(source: try Self.source(peers: Self.peersJSON))
        await vm.refresh()
        #expect(vm.peers?.total == 3)
        #expect(vm.peers?.inbound == 1)
        #expect(vm.peers?.outbound == 2)
        #expect(vm.peers?.onion == 1)
        #expect(vm.peers?.clearnet == 2)
        #expect(vm.peers?.rows.count == 3)
    }

    @Test("mempool fill fraction and sat/vB fee conversion")
    func mempool() async throws {
        let vm = DashboardViewModel(source: try Self.source())
        await vm.refresh()
        #expect(vm.mempool?.count == 3)
        #expect(vm.mempool?.maxBytes == 300_000_000)
        #expect(abs((vm.mempool?.minFeeSatPerVByte ?? 0) - 1.0) < 0.001)  // 0.00001 BTC/kvB
        #expect((vm.mempool?.usageFraction ?? 1) < 0.01)
    }

    @Test("IBD tip reports headers ahead of blocks")
    func initialBlockDownload() async throws {
        let vm = DashboardViewModel(source: try Self.source(info: Self.ibdJSON))
        await vm.refresh()
        #expect(vm.sync?.isInitialBlockDownload == true)
        #expect(vm.sync?.blocks == 100)
        #expect(vm.sync?.headers == 200)
        #expect(vm.sync?.headersAhead == 100)
    }

    // MARK: - Fixtures (lifted from the package's model-decode tests)

    static let prunedJSON = """
    {
      "chain": "main", "blocks": 876000, "headers": 876000,
      "bestblockhash": "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f",
      "difficulty": 110568145977.78, "time": 1713300000, "mediantime": 1713299000,
      "verificationprogress": 0.999999, "initialblockdownload": false,
      "chainwork": "00000000000000000000000000000000000000009c8e007a3e19b3e0b28a5c07",
      "size_on_disk": 12345678901, "pruned": true, "pruneheight": 800000,
      "automatic_pruning": true, "prune_target_size": 1073741824, "warnings": []
    }
    """

    static let ibdJSON = """
    {
      "chain": "signet", "blocks": 100, "headers": 200,
      "bestblockhash": "0000000000000000000000000000000000000000000000000000000000000abc",
      "difficulty": 1.0, "time": 1713300000, "mediantime": 1713299990,
      "verificationprogress": 0.5, "initialblockdownload": true,
      "chainwork": "0000000000000000000000000000000000000000000000000000000000000192",
      "size_on_disk": 12345, "pruned": false, "warnings": []
    }
    """

    static let mempoolJSON = """
    {
      "loaded": true, "size": 3, "bytes": 1234, "usage": 5678,
      "maxmempool": 300000000, "mempoolminfee": 0.00001000,
      "minrelaytxfee": 0.00001000, "unbroadcastcount": 0
    }
    """

    static let peersJSON = """
    [
      {"id":0,"addr":"10.0.0.1:8333","services":"0000000000000409","relaytxes":true,
       "lastsend":1713300000,"lastrecv":1713300000,"bytessent":1000,"bytesrecv":2000,
       "conntime":1713200000,"timeoffset":0,"version":70016,"subver":"/Satoshi:31.0.0/",
       "inbound":false,"startingheight":800000,"synced_headers":876000,"synced_blocks":876000,
       "network":"ipv4","connection_type":"outbound-full-relay","transport_protocol_type":"v2","pingtime":0.05},
      {"id":1,"addr":"abcdefghijklmnop.onion:8333","services":"0000000000000409","relaytxes":false,
       "lastsend":1713300000,"lastrecv":1713300000,"bytessent":500,"bytesrecv":800,
       "conntime":1713200000,"timeoffset":0,"version":70016,"subver":"/Satoshi:31.0.0/",
       "inbound":false,"startingheight":800000,"synced_headers":876000,"synced_blocks":876000,
       "network":"onion","connection_type":"block-relay-only","transport_protocol_type":"v2"},
      {"id":2,"addr":"192.168.1.5:8333","services":"0000000000000409","relaytxes":true,
       "lastsend":1713300000,"lastrecv":1713300000,"bytessent":1200,"bytesrecv":3400,
       "conntime":1713200000,"timeoffset":0,"version":70016,"subver":"/Satoshi:31.0.0/",
       "inbound":true,"startingheight":800000,"synced_headers":876000,"synced_blocks":876000,
       "network":"ipv4","connection_type":"inbound","transport_protocol_type":"v1"}
    ]
    """
}
