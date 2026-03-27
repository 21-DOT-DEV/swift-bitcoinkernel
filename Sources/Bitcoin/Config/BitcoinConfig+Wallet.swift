//
//  BitcoinConfig+Wallet.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

// MARK: - Wallet Options

extension BitcoinConfig {

    /// Disable the wallet and all wallet RPC calls.
    ///
    /// When set, any other wallet option in this config will produce a
    /// `ConfigWarning.walletOptionWithDisableWallet` warning from `validate()`.
    public func disableWallet(_ enabled: Bool = true) -> Self {
        var copy = appending("disablewallet", bool: enabled)
        if enabled { copy = copy.setting(.disableWallet) }
        return copy
    }

    /// Set the pre-generated key pool size.
    public func keypool(_ size: UInt) -> Self {
        appending("keypool", size).setting(.walletOption)
    }

    /// Specify which wallet file(s) to load on startup (relative to `-walletdir`).
    ///
    /// Call multiple times to load multiple wallets.
    public func wallet(_ filename: String) -> Self {
        appending("wallet", filename).setting(.walletOption)
    }

    /// Specify the directory to hold wallet files.
    public func walletDir(_ path: String) -> Self {
        appending("walletdir", path).setting(.walletOption)
    }

    /// Execute a command when a wallet transaction changes.
    ///
    /// `%s` in the command is replaced with the transaction hash.
    public func walletNotify(_ cmd: String) -> Self {
        appending("walletnotify", cmd).setting(.walletOption)
    }

    /// Make the wallet broadcast its transactions to the network.
    public func walletBroadcast(_ enabled: Bool = true) -> Self {
        appending("walletbroadcast", bool: enabled).setting(.walletOption)
    }

    /// Use Replace-By-Fee (RBF) signaling on all new transactions.
    public func walletRbf(_ enabled: Bool = true) -> Self {
        appending("walletrbf", bool: enabled).setting(.walletOption)
    }

    /// Spend unconfirmed change from your own transactions.
    public func spendZeroConfChange(_ enabled: Bool = true) -> Self {
        appending("spendzeroconfchange", bool: enabled).setting(.walletOption)
    }

    /// The default address type for new receiving addresses.
    public func addressType(_ type: AddressType) -> Self {
        appending("addresstype", type.rawValue).setting(.walletOption)
    }

    /// The default address type for change outputs.
    public func changeType(_ type: AddressType) -> Self {
        appending("changetype", type.rawValue).setting(.walletOption)
    }

    /// Minimum fee rate for wallet transactions (BTC/kvB).
    public func minTxFee(_ rate: FeeRate) -> Self {
        appending("mintxfee", rate).setting(.walletOption)
    }

    /// Fee rate to use when sending transactions (BTC/kvB). Use 0 to rely on fee estimation.
    public func payTxFee(_ rate: FeeRate) -> Self {
        appending("paytxfee", rate).setting(.walletOption)
    }

    /// Maximum total fees to use in a single wallet transaction (BTC).
    ///
    /// Set to 0 to disable the cap.
    public func maxTxFee(_ rate: FeeRate) -> Self {
        appending("maxtxfee", rate).setting(.walletOption)
    }

    /// Estimate fee sufficient for confirmation within this many blocks.
    public func txConfirmTarget(_ blocks: UInt) -> Self {
        appending("txconfirmtarget", max(1, blocks)).setting(.walletOption)
    }

    /// Group inputs by address to avoid linking addresses.
    public func avoidPartialSpends(_ enabled: Bool = true) -> Self {
        appending("avoidpartialspends", bool: enabled).setting(.walletOption)
    }

    /// Fallback fee rate if fee estimation is unavailable (BTC/kvB).
    public func fallbackFee(_ rate: FeeRate) -> Self {
        appending("fallbackfee", rate).setting(.walletOption)
    }

    /// Fee rate below which change outputs are omitted as dust (BTC/kvB).
    public func discardFee(_ rate: FeeRate) -> Self {
        appending("discardfee", rate).setting(.walletOption)
    }
}
