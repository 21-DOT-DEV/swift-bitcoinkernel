//
//  EnvelopeDecodingTests.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
import Foundation
@testable import Bitcoin

/// Unit tests for JSON-RPC envelope decoding.
/// Validates the contract between `bitcoin_rpc.cpp`'s envelope format
/// and Swift's `JSONRPCResponse` decoder — no running daemon needed.
@Suite("Envelope Decoding")
struct EnvelopeDecodingTests {

    // MARK: - Success Envelopes

    @Test("Integer result decodes correctly")
    func integerResult() throws {
        let json = #"{"result":123,"error":null,"id":"1"}"#
        let response = try JSONDecoder().decode(JSONRPCResponse<Int>.self, from: Data(json.utf8))

        #expect(response.error == nil)
        #expect(response.id == "1")
        #expect(response.result == 123)
    }

    @Test("String result decodes correctly")
    func stringResult() throws {
        let json = #"{"result":"Bitcoin Core stopping","error":null,"id":"1"}"#
        let response = try JSONDecoder().decode(JSONRPCResponse<String>.self, from: Data(json.utf8))

        #expect(response.error == nil)
        #expect(response.result == "Bitcoin Core stopping")
    }

    @Test("Null result decodes correctly")
    func nullResult() throws {
        let json = #"{"result":null,"error":null,"id":"1"}"#
        let response = try JSONDecoder().decode(JSONRPCResponse<String?>.self, from: Data(json.utf8))

        #expect(response.error == nil)
        #expect(response.result == nil)
    }

    // MARK: - Error Envelopes

    @Test("RPC error decodes correctly")
    func rpcError() throws {
        let json = #"{"result":null,"error":{"code":-32601,"message":"Method not found"},"id":"1"}"#
        let response = try JSONDecoder().decode(JSONRPCResponse<Int>.self, from: Data(json.utf8))

        let error = try #require(response.error)
        #expect(error.code == -32601)
        #expect(error.message == "Method not found")
    }

    @Test("Internal error decodes correctly")
    func internalError() throws {
        let json = #"{"result":null,"error":{"code":-32603,"message":"something went wrong"},"id":"1"}"#
        let response = try JSONDecoder().decode(JSONRPCResponse<Int>.self, from: Data(json.utf8))

        let error = try #require(response.error)
        #expect(error.code == -32603)
        #expect(error.message == "something went wrong")
    }

    // MARK: - Complex Result Envelopes

    @Test("BlockchainInfo result decodes correctly")
    func blockchainInfoResult() throws {
        let json = """
        {"result":{"chain":"main","blocks":0,"headers":0,"bestblockhash":"000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f","difficulty":1.0,"time":1231006505,"mediantime":1231006505,"verificationprogress":1.0,"initialblockdownload":true,"chainwork":"0000000000000000000000000000000000000000000000000000000100010001","size_on_disk":285,"pruned":true,"pruneheight":0,"automatic_pruning":true,"prune_target_size":576716800,"warnings":[]},"error":null,"id":"1"}
        """
        let response = try JSONDecoder().decode(JSONRPCResponse<BlockchainInfo>.self, from: Data(json.utf8))

        #expect(response.error == nil)
        let info = try #require(response.result)
        #expect(info.chain == "main")
        #expect(info.blocks == 0)
    }
}
