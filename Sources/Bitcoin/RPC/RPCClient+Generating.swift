//
//  RPCClient+Generating.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//


// MARK: - Generating RPCs
// https://developer.bitcoin.org/reference/rpc/#generating-rpcs

extension RPCClient {

    /// Mines a block with specified transactions.
    ///
    /// - Parameters:
    ///   - output: The address or descriptor to send the newly generated bitcoin to.
    ///   - transactions: An array of hex strings which are either txids or raw transactions.
    public func generateBlock(output: String, transactions: [String] = []) async throws -> GeneratedBlock {
        try await send("generateblock", params: [.string(output), .encodable(transactions)])
    }

    /// Mines blocks immediately to a specified address (regtest only).
    ///
    /// - Parameters:
    ///   - nBlocks: How many blocks are generated immediately.
    ///   - address: The address to send the newly generated bitcoin to.
    ///   - maxTries: How many iterations to try (default 1000000).
    /// - Returns: Array of hashes of blocks generated.
    public func generateToAddress(nBlocks: Int, address: String, maxTries: Int = 1_000_000) async throws -> [String] {
        try await send("generatetoaddress", params: [.int(nBlocks), .string(address), .int(maxTries)])
    }

    /// Mines blocks immediately to a specified descriptor (regtest only).
    ///
    /// - Parameters:
    ///   - nBlocks: How many blocks are generated immediately.
    ///   - descriptor: The descriptor to send the newly generated bitcoin to.
    ///   - maxTries: How many iterations to try (default 1000000).
    /// - Returns: Array of hashes of blocks generated.
    public func generateToDescriptor(nBlocks: Int, descriptor: String, maxTries: Int = 1_000_000) async throws -> [String] {
        try await send("generatetodescriptor", params: [.int(nBlocks), .string(descriptor), .int(maxTries)])
    }
}
