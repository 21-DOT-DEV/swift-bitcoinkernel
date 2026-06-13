//
//  ConfigClientTests.swift
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

// MARK: - Endpoint & Cookie Derivation

@Suite("Config Client Derivation")
struct ConfigClientDerivationTests {

    @Test("resolvedRPCPort uses the network default when no override is set")
    func defaultPort() {
        #expect(BitcoinConfig.mainnet().resolvedRPCPort == 8332)
        #expect(BitcoinConfig.regtest().resolvedRPCPort == 18443)
        #expect(BitcoinConfig.signet().resolvedRPCPort == 38332)
    }

    @Test("resolvedRPCPort honors an explicit rpcPort override")
    func overridePort() {
        #expect(BitcoinConfig.regtest().rpcPort(29999).resolvedRPCPort == 29999)
    }

    @Test("rpcEndpoint reflects the resolved port")
    func endpoint() {
        #expect(BitcoinConfig.regtest().rpcEndpoint == URL(string: "http://127.0.0.1:18443")!)
        #expect(BitcoinConfig.regtest().rpcPort(29999).rpcEndpoint == URL(string: "http://127.0.0.1:29999")!)
    }

    @Test("cookieURL is nil until a data directory is set")
    func cookieNilWithoutDataDir() {
        #expect(BitcoinConfig.regtest().cookieURL == nil)
        #expect(BitcoinConfig.regtest().server().cookieURL == nil)
    }

    @Test("cookieURL nests under the network subdirectory")
    func cookieSubdir() {
        let dir = "/tmp/btc"
        let base = URL(fileURLWithPath: dir)
        #expect(BitcoinConfig.mainnet().dataDir(dir).cookieURL
            == base.appendingPathComponent(".cookie"))
        #expect(BitcoinConfig.regtest().dataDir(dir).cookieURL
            == base.appendingPathComponent("regtest").appendingPathComponent(".cookie"))
        #expect(BitcoinConfig.signet().dataDir(dir).cookieURL
            == base.appendingPathComponent("signet").appendingPathComponent(".cookie"))
        #expect(BitcoinConfig.testnet4().dataDir(dir).cookieURL
            == base.appendingPathComponent("testnet4").appendingPathComponent(".cookie"))
    }

    @Test("dataDirName matches Bitcoin Core's on-disk layout")
    func dataDirNames() {
        #expect(Mainnet.dataDirName == "")
        #expect(Regtest.dataDirName == "regtest")
        #expect(Signet.dataDirName == "signet")
        #expect(Testnet.dataDirName == "testnet3")
        #expect(Testnet4.dataDirName == "testnet4")
    }
}
