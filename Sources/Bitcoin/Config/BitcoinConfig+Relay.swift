//
//  BitcoinConfig+Relay.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

// MARK: - Transaction Relay Options

extension BitcoinConfig {

    /// Minimum relay fee rate — transactions below this rate are not relayed (BTC/kvB).
    public func minRelayTxFee(_ rate: FeeRate) -> Self {
        appending("minrelaytxfee", rate)
    }

    /// Minimum fee rate increment for mempool limiting or BIP 125 replacement (BTC/kvB).
    public func incrementalRelayFee(_ rate: FeeRate) -> Self {
        appending("incrementalrelayfee", rate)
    }

    /// Relay and mine `OP_RETURN` data carrier transactions.
    public func dataCarrier(_ enabled: Bool = true) -> Self {
        appending("datacarrier", bool: enabled)
    }

    /// Maximum bytes of data in `OP_RETURN` outputs (default 83).
    public func dataCarrierSize(_ bytes: UInt) -> Self {
        appending("datacarriersize", bytes)
    }

    /// Equivalent number of bytes per sigop in transactions for relay/mining.
    public func bytesPerSigOp(_ bytes: UInt) -> Self {
        appending("bytespersigop", bytes)
    }

    /// Relay non-standard transactions that are otherwise rejected.
    ///
    /// Only useful on test networks; has no effect on mainnet.
    public func acceptNonStdTxn(_ enabled: Bool = true) -> Self {
        appending("acceptnonstdtxn", bool: enabled)
    }

    /// Fee rate used to define dust outputs (BTC/kvB).
    ///
    /// Outputs paying less than this to be spent are considered dust.
    public func dustRelayFee(_ rate: FeeRate) -> Self {
        appending("dustrelayfee", rate)
    }

    /// Relay transactions received from whitelisted peers even if they
    /// would normally not be relayed.
    public func whitelistRelay(_ enabled: Bool = true) -> Self {
        appending("whitelistrelay", bool: enabled)
    }

    /// Force relay of transactions from whitelisted peers, bypassing filters.
    public func whitelistForceRelay(_ enabled: Bool = true) -> Self {
        appending("whitelistforcerelay", bool: enabled)
    }

    /// Maximum number of in-mempool ancestors for a transaction (default 25).
    public func limitAncestorCount(_ count: UInt) -> Self {
        appending("limitancestorcount", max(1, count))
    }

    /// Maximum number of in-mempool descendants for a transaction (default 25).
    public func limitDescendantCount(_ count: UInt) -> Self {
        appending("limitdescendantcount", max(1, count))
    }

    /// Allow relay of bare (non-P2SH-wrapped) multisig transactions.
    public func permitBareMultisig(_ enabled: Bool = true) -> Self {
        appending("permitbaremultisig", bool: enabled)
    }
}
