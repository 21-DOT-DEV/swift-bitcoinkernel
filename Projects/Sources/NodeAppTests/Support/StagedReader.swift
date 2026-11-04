//
//  StagedReader.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Bitcoin
@testable import NodeApp

// `NodeRun` and `NodeRunReport` exist only in phone and tablet builds — the
// same compile-time gate as the sources, so these helpers are empty on a
// Mac build.
#if os(iOS)

/// A `DashboardDataSource` whose answers are scripted per question — staged,
/// parked on gates, or failed — while a question the run never asks reports
/// "not part of this test" rather than inventing a reading.
struct StagedReader: DashboardDataSource {
    /// Thrown by a question the test did not script: an unexpected call fails
    /// the question instead of answering with an invented reading.
    struct NotScripted: Error {}

    let blockchain: @Sendable () async throws -> BlockchainInfo
    let network: @Sendable () async throws -> NetworkInfo

    func blockchainInfo() async throws -> BlockchainInfo { try await blockchain() }
    func peers() async throws -> [PeerInfo] { throw NotScripted() }
    func mempoolInfo() async throws -> MempoolInfo { throw NotScripted() }
    func networkInfo() async throws -> NetworkInfo { try await network() }
}

#endif
