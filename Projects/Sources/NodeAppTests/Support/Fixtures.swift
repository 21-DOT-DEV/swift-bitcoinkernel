//
//  Fixtures.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Bitcoin
import Foundation

// `NodeRun` and `NodeRunReport` exist only in phone and tablet builds — the
// same compile-time gate as the sources, so these helpers are empty on a
// Mac build.
#if os(iOS)

/// A `getblockchaininfo` answer mid-IBD — the same shape the production
/// reader returns; the run weighs `chain` and `blocks`. File scope, not a
/// suite member, so the `@Sendable` closures running inside the question
/// bound can reach it without hopping actors.
func decodeBlockchainInfo() throws -> BlockchainInfo {
    try JSONDecoder().decode(
        BlockchainInfo.self,
        from: Data(
            """
            {"chain":"signet","blocks":100,"headers":200,
             "bestblockhash":"0000000000000000000000000000000000000000000000000000000000000abc",
             "difficulty":1.0,"time":1713300000,"mediantime":1713299990,
             "verificationprogress":0.5,"initialblockdownload":true,
             "chainwork":"0000000000000000000000000000000000000000000000000000000000000192",
             "size_on_disk":12345,"pruned":false,"warnings":[]}
            """.utf8))
}

/// A `getnetworkinfo` answer reporting two connections — the count the
/// run's last question is for; the rest exist because the decoder
/// requires them.
func decodeNetworkInfo() throws -> NetworkInfo {
    try JSONDecoder().decode(
        NetworkInfo.self,
        from: Data(
            """
            {"version":270000,"subversion":"/Satoshi:29.0.0/","protocolversion":70016,
             "localservices":"0000000000000409","localservicesnames":["NETWORK","WITNESS"],
             "localrelay":true,"timeoffset":0,"networkactive":true,
             "connections":2,"connections_in":0,"connections_out":2,
             "networks":[],"relayfee":0.00001,"incrementalfee":0.00001,
             "localaddresses":[],"warnings":[]}
            """.utf8))
}

/// Whether `a` precedes `b` in a recorded call list — false when either was
/// never called, so a missing read fails the expectation rather than
/// crashing on a force-unwrap.
func before(_ a: String, _ b: String, in calls: [String]) -> Bool {
    guard let first = calls.firstIndex(of: a),
          let second = calls.firstIndex(of: b) else { return false }
    return first < second
}

/// The wall-clock instant the watch tests' `now:` returns — fixed so a
/// fixture's `time` field decides fresh vs stale deterministically. File
/// scope so the `@Sendable` question closures can reach it without an
/// actor hop.
let watchNow = Date(timeIntervalSince1970: 1_713_300_000)

/// A `getblockchaininfo` answer with the fields the watch weighs
/// scripted: the flag, the gap, and the tip's own timestamp — which
/// defaults to two hours behind `watchNow`, stale past the freshness
/// threshold, so the default answer is a still-syncing one.
func decodeWatchInfo(
    blocks: Int = 100, headers: Int = 200,
    ibd: Bool = true, chain: String = "signet",
    tip: TimeInterval = watchNow.timeIntervalSince1970 - 7_200
) throws -> BlockchainInfo {
    let tip = Int(tip)
    return try JSONDecoder().decode(
        BlockchainInfo.self,
        from: Data(
            """
            {"chain":"\(chain)","blocks":\(blocks),"headers":\(headers),
             "bestblockhash":"0000000000000000000000000000000000000000000000000000000000000abc",
             "difficulty":1.0,"time":\(tip),"mediantime":\(tip - 10),
             "verificationprogress":0.5,"initialblockdownload":\(ibd),
             "chainwork":"0000000000000000000000000000000000000000000000000000000000000192",
             "size_on_disk":12345,"pruned":false,"warnings":[]}
            """.utf8))
}

#endif
