//
//  BitcoinConfig+ZMQ.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

// MARK: - ZMQ Publish Options

extension BitcoinConfig {

    // MARK: Endpoints

    /// Publish raw block data to the given ZMQ endpoint.
    ///
    /// Subscribers receive the full serialised block for each new tip.
    public func zmqPubRawBlock(_ endpoint: ZMQEndpoint) -> Self {
        appending("zmqpubrawblock", endpoint)
    }

    /// Publish raw transaction data to the given ZMQ endpoint.
    ///
    /// Subscribers receive the full serialised transaction for every
    /// transaction added to the mempool or included in a block.
    public func zmqPubRawTx(_ endpoint: ZMQEndpoint) -> Self {
        appending("zmqpubrawtx", endpoint)
    }

    /// Publish block hashes (32 bytes) to the given ZMQ endpoint.
    public func zmqPubHashBlock(_ endpoint: ZMQEndpoint) -> Self {
        appending("zmqpubhashblock", endpoint)
    }

    /// Publish transaction hashes (32 bytes) to the given ZMQ endpoint.
    public func zmqPubHashTx(_ endpoint: ZMQEndpoint) -> Self {
        appending("zmqpubhashtx", endpoint)
    }

    /// Publish mempool and chain sequence events to the given ZMQ endpoint.
    ///
    /// Messages carry a sequence number and an event tag so subscribers can
    /// detect missed notifications and re-sync as needed.
    public func zmqPubSequence(_ endpoint: ZMQEndpoint) -> Self {
        appending("zmqpubsequence", endpoint)
    }

    // MARK: High-Water Marks

    /// Maximum number of raw block messages queued before dropping (default 1000).
    public func zmqPubRawBlockHwm(_ count: UInt) -> Self {
        appending("zmqpubrawblockhwm", count)
    }

    /// Maximum number of raw transaction messages queued before dropping (default 1000).
    public func zmqPubRawTxHwm(_ count: UInt) -> Self {
        appending("zmqpubrawtxhwm", count)
    }

    /// Maximum number of block-hash messages queued before dropping (default 1000).
    public func zmqPubHashBlockHwm(_ count: UInt) -> Self {
        appending("zmqpubhashblockhwm", count)
    }

    /// Maximum number of transaction-hash messages queued before dropping (default 1000).
    public func zmqPubHashTxHwm(_ count: UInt) -> Self {
        appending("zmqpubhashtxhwm", count)
    }

    /// Maximum number of sequence messages queued before dropping (default 1000).
    public func zmqPubSequenceHwm(_ count: UInt) -> Self {
        appending("zmqpubsequencehwm", count)
    }
}
