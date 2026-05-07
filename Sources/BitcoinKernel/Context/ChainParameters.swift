//
//  ChainParameters.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

internal import libbitcoinkernel

/// Chain parameters describing the consensus rules, genesis block, subsidy
/// schedule, and soft-fork activation heights of a specific Bitcoin network.
///
/// Wraps Bitcoin Core's [`CChainParams`](https://github.com/bitcoin/bitcoin/blob/master/src/kernel/chainparams.h).
/// Each ``ChainType`` selects a distinct set of parameters — mainnet's
/// consensus differs from regtest's by activation heights, subsidy halving
/// interval, and PoW difficulty floor, among many other fields.
///
/// Construct once per ``Context``; attach via
/// ``ContextOptions/setChainParams(_:)``. The kernel copies parameters
/// internally on that call, so this object can be released afterward.
///
/// Wraps the opaque `btck_ChainParameters` type; `deinit` calls
/// `btck_chain_parameters_destroy` when the last Swift reference drops.
public final class ChainParameters: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Creates chain parameters for the given chain type.
    ///
    /// - Parameter chainType: Which Bitcoin network to configure for —
    ///   mainnet, testnet3, testnet4, signet, or regtest. See ``ChainType``.
    public init(_ chainType: ChainType) {
        self.pointer = btck_chain_parameters_create(chainType.rawValue)
    }

    deinit {
        btck_chain_parameters_destroy(pointer)
    }
}
