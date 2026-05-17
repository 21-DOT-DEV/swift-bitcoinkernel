//
//  RPCClient+Util.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

// MARK: - Util RPCs
// https://developer.bitcoin.org/reference/rpc/#util-rpcs

extension RPCClient {

    /// Estimates the approximate fee per kilobyte needed for a transaction.
    ///
    /// - Parameters:
    ///   - confTarget: Confirmation target in blocks (1–1008).
    ///   - mode: Estimation mode: "UNSET", "ECONOMICAL", or "CONSERVATIVE" (default).
    public func estimateSmartFee(confTarget: Int, mode: String = "CONSERVATIVE") async throws -> SmartFeeEstimate {
        try await send("estimatesmartfee", params: [.int(confTarget), .string(mode)])
    }

    /// Validates a bitcoin address.
    public func validateAddress(address: String) async throws -> AddressValidation {
        try await send("validateaddress", params: [.string(address)])
    }

    /// Verifies a signed message.
    ///
    /// - Returns: `true` if the signature is valid.
    public func verifyMessage(address: String, signature: String, message: String) async throws -> Bool {
        try await send("verifymessage", params: [.string(address), .string(signature), .string(message)])
    }

    /// Signs a message with a private key.
    ///
    /// - Returns: The base64 signature.
    public func signMessageWithPrivKey(privKey: String, message: String) async throws -> String {
        try await send("signmessagewithprivkey", params: [.string(privKey), .string(message)])
    }

    /// Creates a multisig address.
    ///
    /// - Parameters:
    ///   - nRequired: The number of required signatures.
    ///   - keys: Public keys or addresses.
    ///   - addressType: Address type: "legacy", "p2sh-segwit", or "bech32" (optional).
    public func createMultisig(nRequired: Int, keys: [String], addressType: String? = nil) async throws -> MultisigResult {
        var params: [RPCParam] = [.int(nRequired), .encodable(keys)]
        if let addressType { params.append(.string(addressType)) }
        return try await send("createmultisig", params: params)
    }

    /// Derives one or more addresses from a descriptor.
    ///
    /// - Parameters:
    ///   - descriptor: The output descriptor.
    ///   - range: Range for ranged descriptors (e.g., `[0, 10]`).
    public func deriveAddresses(descriptor: String, range: [Int]? = nil) async throws -> [String] {
        var params: [RPCParam] = [.string(descriptor)]
        if let range { params.append(.encodable(range)) }
        return try await send("deriveaddresses", params: params)
    }

    /// Returns information about an output descriptor.
    public func getDescriptorInfo(descriptor: String) async throws -> DescriptorInfo {
        try await send("getdescriptorinfo", params: [.string(descriptor)])
    }

    /// Returns the status of one or all available indices.
    ///
    /// - Parameter indexName: Filter results for an index name (optional).
    public func getIndexInfo(indexName: String? = nil) async throws -> [String: IndexInfo] {
        var params: [RPCParam] = []
        if let indexName { params.append(.string(indexName)) }
        return try await send("getindexinfo", params: params)
    }

    /// Returns raw fee estimate data (for advanced fee estimation).
    ///
    /// - Parameters:
    ///   - confTarget: Confirmation target in blocks.
    ///   - threshold: Required proportion of transactions that must have been
    ///     confirmed within confTarget. Higher values are more conservative (default 0.95).
    /// - Returns: Raw JSON with bucket data, pass/fail counts, and fee estimates.
    public func estimateRawFee(confTarget: Int, threshold: Double = 0.95) async throws -> Data {
        try await call("estimaterawfee", params: [.int(confTarget), .double(threshold)])
    }
}
