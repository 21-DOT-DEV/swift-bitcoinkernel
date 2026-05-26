//
//  NetworkModelTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
import Foundation
@testable import Bitcoin

/// Decode tests for Phase 5: Network models.
@Suite("Network Model Decoding")
struct NetworkModelTests {

    // MARK: - NetworkInfo

    @Test("NetworkInfo decodes from Core JSON")
    func networkInfoDecode() throws {
        let json = """
        {
          "version": 310000,
          "subversion": "/Satoshi:31.0.0/",
          "protocolversion": 70016,
          "localservices": "0000000000000c09",
          "localservicesnames": ["NETWORK", "WITNESS", "NETWORK_LIMITED", "P2P_V2"],
          "localrelay": true,
          "timeoffset": 0,
          "connections": 10,
          "connections_in": 2,
          "connections_out": 8,
          "networkactive": true,
          "networks": [
            {
              "name": "ipv4",
              "limited": false,
              "reachable": true,
              "proxy": "",
              "proxy_randomize_credentials": false
            },
            {
              "name": "ipv6",
              "limited": false,
              "reachable": true,
              "proxy": "",
              "proxy_randomize_credentials": false
            }
          ],
          "relayfee": 0.00001000,
          "incrementalfee": 0.00001000,
          "localaddresses": [
            {"address": "1.2.3.4", "port": 8333, "score": 4}
          ],
          "warnings": []
        }
        """
        let info = try JSONDecoder().decode(NetworkInfo.self, from: Data(json.utf8))
        #expect(info.version == 310000)
        #expect(info.subversion == "/Satoshi:31.0.0/")
        #expect(info.connections == 10)
        #expect(info.connectionsIn == 2)
        #expect(info.connectionsOut == 8)
        #expect(info.networkactive)
        #expect(info.networks.count == 2)
        #expect(info.networks[0].name == "ipv4")
        #expect(info.networks[0].reachable)
        #expect(info.relayfee == 0.00001)
        #expect(info.localaddresses.count == 1)
        #expect(info.localaddresses[0].port == 8333)
        #expect(info.warnings.isEmpty)
    }

    @Test("NetworkInfo decodes with empty networks and local addresses")
    func networkInfoMinimalDecode() throws {
        let json = """
        {
          "version": 310000,
          "subversion": "/Satoshi:31.0.0/",
          "protocolversion": 70016,
          "localservices": "0000000000000000",
          "localservicesnames": [],
          "localrelay": false,
          "timeoffset": 0,
          "connections": 0,
          "connections_in": 0,
          "connections_out": 0,
          "networkactive": false,
          "networks": [],
          "relayfee": 0.00001000,
          "incrementalfee": 0.00001000,
          "localaddresses": [],
          "warnings": []
        }
        """
        let info = try JSONDecoder().decode(NetworkInfo.self, from: Data(json.utf8))
        #expect(info.connections == 0)
        #expect(!info.networkactive)
        #expect(info.networks.isEmpty)
        #expect(info.localaddresses.isEmpty)
    }

    // MARK: - PeerInfo

    @Test("PeerInfo decodes from Core JSON")
    func peerInfoDecode() throws {
        let json = """
        {
          "id": 1,
          "addr": "192.168.1.1:8333",
          "addrbind": "0.0.0.0:45678",
          "addrlocal": "1.2.3.4:8333",
          "network": "ipv4",
          "services": "0000000000000c09",
          "servicesnames": ["NETWORK", "WITNESS"],
          "relaytxes": true,
          "lastsend": 1713300000,
          "lastrecv": 1713300001,
          "last_transaction": 1713299000,
          "last_block": 1713298000,
          "bytessent": 123456,
          "bytesrecv": 654321,
          "conntime": 1713200000,
          "timeoffset": -1,
          "pingtime": 0.05,
          "minping": 0.03,
          "version": 70016,
          "subver": "/Satoshi:31.0.0/",
          "inbound": false,
          "bip152_hb_to": true,
          "bip152_hb_from": false,
          "startingheight": 876000,
          "presynced_headers": -1,
          "synced_headers": 876001,
          "synced_blocks": 876001,
          "inflight": [],
          "addr_relay_enabled": true,
          "addr_processed": 1000,
          "addr_rate_limited": 0,
          "permissions": [],
          "minfeefilter": 0.00001000,
          "bytessent_per_msg": {"inv": 1000, "tx": 5000},
          "bytesrecv_per_msg": {"inv": 2000, "block": 50000},
          "connection_type": "outbound-full-relay",
          "transport_protocol_type": "v2",
          "session_id": "aabbccdd"
        }
        """
        let peer = try JSONDecoder().decode(PeerInfo.self, from: Data(json.utf8))
        #expect(peer.id == 1)
        #expect(peer.addr == "192.168.1.1:8333")
        #expect(peer.network == "ipv4")
        #expect(!peer.inbound)
        #expect(peer.lastsend.seconds == 1713300000)
        #expect(peer.lastrecv.seconds == 1713300001)
        #expect(peer.lastTransaction?.seconds == 1713299000)
        #expect(peer.lastBlock?.seconds == 1713298000)
        #expect(peer.conntime.seconds == 1713200000)
        #expect(peer.syncedHeaders == 876001)
        #expect(peer.syncedBlocks == 876001)
        #expect(peer.connectionType == "outbound-full-relay")
        #expect(peer.transportProtocolType == "v2")
        #expect(peer.bytessentPerMsg?["inv"] == 1000)
    }

    @Test("PeerInfo decodes with minimal optional fields")
    func peerInfoMinimalDecode() throws {
        let json = """
        {
          "id": 0,
          "addr": "127.0.0.1:18444",
          "services": "0000000000000000",
          "relaytxes": false,
          "lastsend": 0,
          "lastrecv": 0,
          "bytessent": 0,
          "bytesrecv": 0,
          "conntime": 0,
          "timeoffset": 0,
          "version": 70016,
          "subver": "/Satoshi:31.0.0/",
          "inbound": true,
          "startingheight": 0,
          "synced_headers": -1,
          "synced_blocks": -1
        }
        """
        let peer = try JSONDecoder().decode(PeerInfo.self, from: Data(json.utf8))
        #expect(peer.id == 0)
        #expect(peer.inbound)
        #expect(peer.lastsend.seconds == 0)
        #expect(peer.lastrecv.seconds == 0)
        #expect(peer.conntime.seconds == 0)
        #expect(peer.lastTransaction == nil)
        #expect(peer.lastBlock == nil)
        #expect(peer.pingtime == nil)
        #expect(peer.connectionType == nil)
        #expect(peer.network == nil)
    }

    // MARK: - NetTotals

    @Test("NetTotals decodes from Core JSON")
    func netTotalsDecode() throws {
        let json = """
        {
          "totalbytesrecv": 123456789,
          "totalbytessent": 987654321,
          "timemillis": 1713300000000,
          "uploadtarget": {
            "timeframe": 86400,
            "target": 0,
            "target_reached": false,
            "serve_historical_blocks": true,
            "bytes_left_in_cycle": 0,
            "time_left_in_cycle": 43200
          }
        }
        """
        let n = try JSONDecoder().decode(NetTotals.self, from: Data(json.utf8))
        #expect(n.totalbytesrecv == 123456789)
        #expect(n.totalbytessent == 987654321)
        #expect(n.uploadtarget.timeframe == 86400)
        #expect(!n.uploadtarget.targetReached)
        #expect(n.uploadtarget.serveHistoricalBlocks)
    }

    // MARK: - NodeAddress

    @Test("NodeAddress decodes from Core JSON")
    func nodeAddressDecode() throws {
        let json = """
        {
          "time": 1713300000,
          "services": 1033,
          "address": "192.168.1.1",
          "port": 8333,
          "network": "ipv4"
        }
        """
        let a = try JSONDecoder().decode(NodeAddress.self, from: Data(json.utf8))
        #expect(a.time.seconds == 1713300000)
        #expect(a.address == "192.168.1.1")
        #expect(a.port == 8333)
        #expect(a.network == "ipv4")
    }

    // MARK: - AddedNodeInfo

    @Test("AddedNodeInfo decodes from Core JSON")
    func addedNodeInfoDecode() throws {
        let json = """
        {
          "addednode": "192.168.1.1:8333",
          "connected": true,
          "addresses": [
            {"address": "192.168.1.1:8333", "connected": "outbound"}
          ]
        }
        """
        let info = try JSONDecoder().decode(AddedNodeInfo.self, from: Data(json.utf8))
        #expect(info.addednode == "192.168.1.1:8333")
        #expect(info.connected)
        #expect(info.addresses.count == 1)
        #expect(info.addresses[0].connected == "outbound")
    }

    // MARK: - BannedInfo

    @Test("BannedInfo decodes from Core JSON")
    func bannedInfoDecode() throws {
        let json = """
        {
          "address": "192.168.1.0/24",
          "ban_created": 1713300000,
          "ban_expires": 1713386400,
          "ban_duration": 86400,
          "time_remaining": 43200
        }
        """
        let b = try JSONDecoder().decode(BannedInfo.self, from: Data(json.utf8))
        #expect(b.address == "192.168.1.0/24")
        #expect(b.banCreated == 1713300000)
        #expect(b.banDuration == 86400)
        #expect(b.timeRemaining == 43200)
    }

    // MARK: - ZMQNotification

    @Test("ZMQNotification decodes from Core JSON")
    func zmqNotificationDecode() throws {
        let json = """
        {"type": "pubhashblock", "address": "tcp://127.0.0.1:29000", "hwm": 1000}
        """
        let z = try JSONDecoder().decode(ZMQNotification.self, from: Data(json.utf8))
        #expect(z.type == "pubhashblock")
        #expect(z.address == "tcp://127.0.0.1:29000")
        #expect(z.hwm == 1000)
    }

    @Test("ZMQNotification array decodes")
    func zmqNotificationArrayDecode() throws {
        let json = """
        [
          {"type": "pubhashblock", "address": "tcp://127.0.0.1:29000", "hwm": 1000},
          {"type": "pubrawtx", "address": "tcp://127.0.0.1:29001", "hwm": 1000}
        ]
        """
        let notifications = try JSONDecoder().decode([ZMQNotification].self, from: Data(json.utf8))
        #expect(notifications.count == 2)
        #expect(notifications[1].type == "pubrawtx")
    }
}
