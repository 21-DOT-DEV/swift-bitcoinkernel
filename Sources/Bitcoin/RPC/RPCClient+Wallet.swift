//
//  RPCClient+Wallet.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

#if Xcode || ENABLE_WALLET

// MARK: - Wallet RPCs
// https://developer.bitcoin.org/reference/rpc/#wallet-rpcs
//
// Wallet RPCs require a wallet name for path scoping (/wallet/<name>).
// All methods take a `wallet` parameter for this purpose.

extension RPCClient {

    // MARK: Wallet Management

    /// Returns wallet state information.
    public func getWalletInfo(wallet: String) async throws -> WalletInfo {
        try await send("getwalletinfo", wallet: wallet)
    }

    /// Returns a list of wallet directories.
    public func listWalletDir() async throws -> Data {
        try await call("listwalletdir")
    }

    /// Returns a list of currently loaded wallets.
    public func listWallets() async throws -> [String] {
        try await send("listwallets")
    }

    /// Creates a new wallet.
    ///
    /// - Parameters:
    ///   - name: The wallet name.
    ///   - disablePrivateKeys: Create a watch-only wallet (default false).
    ///   - blank: Create a blank wallet with no keys (default false).
    ///   - passphrase: Encrypt the wallet with this passphrase.
    ///   - avoidReuse: Track coin reuse (default false).
    ///   - descriptors: Use descriptor wallets (default true).
    ///   - loadOnStartup: Load wallet on startup (nil = no preference).
    public func createWallet(
        name: String,
        disablePrivateKeys: Bool = false,
        blank: Bool = false,
        passphrase: String = "",
        avoidReuse: Bool = false,
        descriptors: Bool = true,
        loadOnStartup: Bool? = nil
    ) async throws -> CreateWalletResult {
        var params: [RPCParam] = [
            .string(name), .bool(disablePrivateKeys), .bool(blank),
            .string(passphrase), .bool(avoidReuse), .bool(descriptors)
        ]
        if let load = loadOnStartup { params.append(.bool(load)) } else { params.append(.null) }
        return try await send("createwallet", params: params)
    }

    /// Loads a wallet from the wallet directory.
    ///
    /// - Parameters:
    ///   - filename: The wallet directory or .dat file.
    ///   - loadOnStartup: Load wallet on startup (nil = no preference).
    public func loadWallet(filename: String, loadOnStartup: Bool? = nil) async throws -> CreateWalletResult {
        var params: [RPCParam] = [.string(filename)]
        if let load = loadOnStartup { params.append(.bool(load)) } else { params.append(.null) }
        return try await send("loadwallet", params: params)
    }

    /// Unloads a wallet.
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - loadOnStartup: Remove from startup loading (nil = no preference).
    public func unloadWallet(wallet: String, loadOnStartup: Bool? = nil) async throws {
        var params: [RPCParam] = []
        params.append(.string(wallet))
        if let load = loadOnStartup { params.append(.bool(load)) } else { params.append(.null) }
        try await sendVoid("unloadwallet", params: params)
    }

    /// Sets a wallet flag.
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - flag: The flag name (e.g., "avoid_reuse").
    ///   - value: The flag value (default true).
    public func setWalletFlag(wallet: String, flag: String, value: Bool = true) async throws -> Data {
        try await callWallet("setwalletflag", wallet: wallet, params: [.string(flag), .bool(value)])
    }

    /// Migrates a legacy wallet to descriptor wallet (v25+).
    ///
    /// - Parameter wallet: The wallet name to migrate.
    public func migrateWallet(wallet: String) async throws -> Data {
        try await callWallet("migratewallet", wallet: wallet)
    }

    /// Returns information about HD keys in the wallet (v25+).
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - activeOnly: Only return active HD keys (default false).
    public func getHDKeys(wallet: String, activeOnly: Bool = false) async throws -> Data {
        try await callWallet("gethdkeys", wallet: wallet, params: [.bool(activeOnly)])
    }

    /// Creates a wallet descriptor for the given address type (v25+).
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - addressType: "legacy", "p2sh-segwit", "bech32", or "bech32m".
    ///   - options: Optional options object with `hdkey` and `internal` fields.
    public func createWalletDescriptor(
        wallet: String,
        addressType: String,
        options: [String: RPCParam]? = nil
    ) async throws -> Data {
        var params: [RPCParam] = [.string(addressType)]
        if let options { params.append(.encodable(options)) }
        return try await callWallet("createwalletdescriptor", wallet: wallet, params: params)
    }

    // MARK: Address RPCs

    /// Returns a new Bitcoin address for receiving payments.
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - label: The label for the address (default "").
    ///   - addressType: "legacy", "p2sh-segwit", "bech32", or "bech32m" (optional).
    public func getNewAddress(wallet: String, label: String = "", addressType: String? = nil) async throws -> String {
        var params: [RPCParam] = [.string(label)]
        if let addressType { params.append(.string(addressType)) }
        return try await send("getnewaddress", wallet: wallet, params: params)
    }

    /// Returns a new address for receiving change.
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - addressType: "legacy", "p2sh-segwit", "bech32", or "bech32m" (optional).
    public func getRawChangeAddress(wallet: String, addressType: String? = nil) async throws -> String {
        var params: [RPCParam] = []
        if let addressType { params.append(.string(addressType)) }
        return try await send("getrawchangeaddress", wallet: wallet, params: params)
    }

    /// Sets the label for an address.
    public func setLabel(wallet: String, address: String, label: String) async throws {
        try await sendVoid("setlabel", wallet: wallet, params: [.string(address), .string(label)])
    }

    /// Returns information about the given bitcoin address.
    public func getAddressInfo(wallet: String, address: String) async throws -> Data {
        try await callWallet("getaddressinfo", wallet: wallet, params: [.string(address)])
    }

    /// Returns addresses grouped by common ownership.
    public func listAddressGroupings(wallet: String) async throws -> Data {
        try await callWallet("listaddressgroupings", wallet: wallet)
    }

    /// Returns addresses assigned to a label.
    public func getAddressesByLabel(wallet: String, label: String) async throws -> Data {
        try await callWallet("getaddressesbylabel", wallet: wallet, params: [.string(label)])
    }

    /// Returns all labels in the wallet.
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - purpose: Filter by address purpose ("send" or "receive").
    public func listLabels(wallet: String, purpose: String? = nil) async throws -> [String] {
        var params: [RPCParam] = []
        if let purpose { params.append(.string(purpose)) }
        return try await send("listlabels", wallet: wallet, params: params)
    }

    /// Refills the keypool.
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - newSize: The new keypool size (default 100).
    public func keypoolRefill(wallet: String, newSize: Int = 100) async throws {
        try await sendVoid("keypoolrefill", wallet: wallet, params: [.int(newSize)])
    }

    /// Displays an address on an external signer (hardware wallet).
    public func walletDisplayAddress(wallet: String, address: String) async throws -> Data {
        try await callWallet("walletdisplayaddress", wallet: wallet, params: [.string(address)])
    }

    // MARK: Balance & Coins

    /// Returns the wallet balance.
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - minConf: Minimum confirmations (default 0).
    ///   - includeWatchOnly: Include watch-only addresses (default true for watch-only wallets).
    ///   - avoidReuse: Only include non-dirty outputs (default true if wallet flag set).
    public func getBalance(wallet: String, minConf: Int = 0, includeWatchOnly: Bool = false, avoidReuse: Bool = true) async throws -> BTCAmount {
        try await send("getbalance", wallet: wallet, params: [.string("*"), .int(minConf), .bool(includeWatchOnly), .bool(avoidReuse)])
    }

    /// Returns all balances in the wallet.
    public func getBalances(wallet: String) async throws -> WalletBalances {
        try await send("getbalances", wallet: wallet)
    }

    /// Returns the total received by an address.
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - address: The bitcoin address.
    ///   - minConf: Minimum confirmations (default 1).
    public func getReceivedByAddress(wallet: String, address: String, minConf: Int = 1) async throws -> BTCAmount {
        try await send("getreceivedbyaddress", wallet: wallet, params: [.string(address), .int(minConf)])
    }

    /// Returns the total received by a label.
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - label: The label.
    ///   - minConf: Minimum confirmations (default 1).
    public func getReceivedByLabel(wallet: String, label: String, minConf: Int = 1) async throws -> BTCAmount {
        try await send("getreceivedbylabel", wallet: wallet, params: [.string(label), .int(minConf)])
    }

    /// Returns unspent transaction outputs.
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - minConf: Minimum confirmations (default 0).
    ///   - maxConf: Maximum confirmations (default 9999999).
    ///   - addresses: Filter to these addresses (optional).
    public func listUnspent(
        wallet: String,
        minConf: Int = 0,
        maxConf: Int = 9_999_999,
        addresses: [String]? = nil
    ) async throws -> [UnspentOutput] {
        var params: [RPCParam] = [.int(minConf), .int(maxConf)]
        if let addresses { params.append(.encodable(addresses)) }
        return try await send("listunspent", wallet: wallet, params: params)
    }

    /// Locks or unlocks unspent outputs.
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - unlock: Whether to unlock (true) or lock (false) the outputs.
    ///   - outputs: The outputs to lock/unlock `[{"txid": ..., "vout": ...}]`.
    public func lockUnspent(wallet: String, unlock: Bool, outputs: [[String: RPCParam]] = []) async throws -> Bool {
        try await send("lockunspent", wallet: wallet, params: [.bool(unlock), .encodable(outputs)])
    }

    /// Returns locked unspent outputs.
    public func listLockUnspent(wallet: String) async throws -> Data {
        try await callWallet("listlockunspent", wallet: wallet)
    }

    // MARK: Send & Spend

    /// Sends bitcoin to an address.
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - address: The destination address.
    ///   - amount: The amount in BTC.
    ///   - comment: A comment for the transaction.
    ///   - commentTo: A comment for the recipient.
    ///   - subtractFeeFromAmount: Deduct fee from the amount (default false).
    ///   - replaceable: Allow RBF (optional).
    ///   - confTarget: Confirmation target in blocks (optional).
    /// - Returns: The transaction id.
    public func sendToAddress(
        wallet: String,
        address: String,
        amount: Double,
        comment: String = "",
        commentTo: String = "",
        subtractFeeFromAmount: Bool = false,
        replaceable: Bool? = nil,
        confTarget: Int? = nil
    ) async throws -> String {
        var params: [RPCParam] = [
            .string(address), .double(amount), .string(comment), .string(commentTo), .bool(subtractFeeFromAmount)
        ]
        if let replaceable { params.append(.bool(replaceable)) }
        else if confTarget != nil { params.append(.null) }
        if let confTarget { params.append(.int(confTarget)) }
        return try await send("sendtoaddress", wallet: wallet, params: params)
    }

    /// Sends to multiple addresses in one transaction.
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - amounts: `{"address": amount, ...}`.
    ///   - minConf: Minimum confirmations for inputs (default 1).
    ///   - comment: A comment for the transaction.
    /// - Returns: The transaction id.
    public func sendMany(
        wallet: String,
        amounts: [String: Double],
        minConf: Int = 1,
        comment: String = ""
    ) async throws -> String {
        try await send("sendmany", wallet: wallet, params: [
            .string(""), .encodable(amounts), .int(minConf), .string(comment)
        ])
    }

    /// Advanced send with coin control and fee options (v21+).
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - outputs: Transaction outputs `[{"address": amount}, {"data": "hex"}]`.
    ///   - options: Options dictionary (conf_target, fee_rate, etc.).
    /// - Returns: Send result with txid or PSBT.
    public func walletSend(
        wallet: String,
        outputs: [[String: RPCParam]],
        options: [String: RPCParam]? = nil
    ) async throws -> SendResult {
        var params: [RPCParam] = [.encodable(outputs)]
        if let options {
            // send(outputs, conf_target, estimate_mode, fee_rate, options)
            params.append(.null) // conf_target — use wallet default
            params.append(.null) // estimate_mode — use wallet default
            params.append(.null) // fee_rate — use wallet default
            params.append(.encodable(options))
        }
        return try await send("send", wallet: wallet, params: params)
    }

    /// Sends all wallet outputs to one or more recipients (v24+, EXPERIMENTAL).
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - recipients: Destination addresses.
    ///   - options: Options dictionary.
    public func sendAll(wallet: String, recipients: [String], options: [String: RPCParam]? = nil) async throws -> SendResult {
        var params: [RPCParam] = [.encodable(recipients)]
        if let options { params.append(.encodable(options)) }
        return try await send("sendall", wallet: wallet, params: params)
    }

    /// Adds inputs to a raw transaction until it has enough value.
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - hex: The hex-encoded raw transaction.
    ///   - options: Funding options (changeAddress, feeRate, etc.).
    public func fundRawTransaction(wallet: String, hex: String, options: [String: RPCParam]? = nil) async throws -> FundRawTransactionResult {
        var params: [RPCParam] = [.string(hex)]
        if let options { params.append(.encodable(options)) }
        return try await send("fundrawtransaction", wallet: wallet, params: params)
    }

    /// Signs a raw transaction with wallet keys.
    public func signRawTransactionWithWallet(wallet: String, hex: String) async throws -> SignedTransaction {
        try await send("signrawtransactionwithwallet", wallet: wallet, params: [.string(hex)])
    }

    /// Bumps the fee of an unconfirmed transaction.
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - txid: The transaction id to bump.
    ///   - options: Options (fee_rate, replaceable, etc.).
    public func bumpFee(wallet: String, txid: String, options: [String: RPCParam]? = nil) async throws -> BumpFeeResult {
        var params: [RPCParam] = [.string(txid)]
        if let options { params.append(.encodable(options)) }
        return try await send("bumpfee", wallet: wallet, params: params)
    }

    /// Bumps the fee of an unconfirmed transaction, returning a PSBT.
    public func psbtBumpFee(wallet: String, txid: String, options: [String: RPCParam]? = nil) async throws -> PSBTBumpFeeResult {
        var params: [RPCParam] = [.string(txid)]
        if let options { params.append(.encodable(options)) }
        return try await send("psbtbumpfee", wallet: wallet, params: params)
    }

    /// Creates and funds a PSBT from wallet inputs.
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - inputs: Transaction inputs `[{"txid": ..., "vout": ...}]` (empty = auto-select).
    ///   - outputs: Transaction outputs `[{"address": amount}]`.
    ///   - locktime: Raw locktime (default 0).
    ///   - options: Funding options.
    public func walletCreateFundedPSBT(
        wallet: String,
        inputs: [[String: RPCParam]] = [],
        outputs: [[String: RPCParam]],
        locktime: Int = 0,
        options: [String: RPCParam]? = nil
    ) async throws -> Data {
        var params: [RPCParam] = [.encodable(inputs), .encodable(outputs), .int(locktime)]
        if let options { params.append(.encodable(options)) }
        return try await callWallet("walletcreatefundedpsbt", wallet: wallet, params: params)
    }

    /// Signs a PSBT with wallet keys.
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - psbt: The PSBT base64 string.
    ///   - signAll: Sign all inputs (default true).
    ///   - sigHashType: Signature hash type (default "DEFAULT").
    public func walletProcessPSBT(
        wallet: String,
        psbt: String,
        signAll: Bool = true,
        sigHashType: String = "DEFAULT"
    ) async throws -> FinalizedPSBT {
        try await send("walletprocesspsbt", wallet: wallet, params: [
            .string(psbt), .bool(signAll), .string(sigHashType)
        ])
    }

    // MARK: Transactions

    /// Returns detailed information about a wallet transaction.
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - txid: The transaction id.
    ///   - includeWatchOnly: Include watch-only addresses (default true for watch-only wallets).
    ///   - verbose: Include decoded transaction details (default false).
    public func getTransaction(wallet: String, txid: String, includeWatchOnly: Bool = false, verbose: Bool = false) async throws -> WalletTransaction {
        try await send("gettransaction", wallet: wallet, params: [.string(txid), .bool(includeWatchOnly), .bool(verbose)])
    }

    /// Returns transactions since a block.
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - blockHash: Return transactions since this block (nil = genesis).
    ///   - targetConfirmations: Wait for this many confirmations (default 1).
    ///   - includeWatchOnly: Include watch-only addresses (default true for watch-only wallets).
    ///   - includeRemoved: Include transactions removed by reorg (default true).
    public func listSinceBlock(
        wallet: String,
        blockHash: String? = nil,
        targetConfirmations: Int = 1,
        includeWatchOnly: Bool = false,
        includeRemoved: Bool = true
    ) async throws -> ListSinceBlockResult {
        var params: [RPCParam] = []
        params.append(blockHash.map { .string($0) } ?? .null)
        params.append(.int(targetConfirmations))
        params.append(.bool(includeWatchOnly))
        params.append(.bool(includeRemoved))
        return try await send("listsinceblock", wallet: wallet, params: params)
    }

    /// Returns recent wallet transactions.
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - label: Filter by label (default "*" = all).
    ///   - count: Number of transactions (default 10).
    ///   - skip: Number to skip (default 0).
    ///   - includeWatchOnly: Include watch-only addresses.
    public func listTransactions(
        wallet: String,
        label: String = "*",
        count: Int = 10,
        skip: Int = 0,
        includeWatchOnly: Bool = false
    ) async throws -> Data {
        try await callWallet("listtransactions", wallet: wallet, params: [
            .string(label), .int(count), .int(skip), .bool(includeWatchOnly)
        ])
    }

    /// Returns amounts received by address.
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - minConf: Minimum confirmations (default 1).
    ///   - includeEmpty: Include addresses with no transactions (default false).
    ///   - includeWatchOnly: Include watch-only addresses.
    public func listReceivedByAddress(
        wallet: String,
        minConf: Int = 1,
        includeEmpty: Bool = false,
        includeWatchOnly: Bool = false
    ) async throws -> Data {
        try await callWallet("listreceivedbyaddress", wallet: wallet, params: [
            .int(minConf), .bool(includeEmpty), .bool(includeWatchOnly)
        ])
    }

    /// Returns amounts received by label.
    public func listReceivedByLabel(
        wallet: String,
        minConf: Int = 1,
        includeEmpty: Bool = false,
        includeWatchOnly: Bool = false
    ) async throws -> Data {
        try await callWallet("listreceivedbylabel", wallet: wallet, params: [
            .int(minConf), .bool(includeEmpty), .bool(includeWatchOnly)
        ])
    }

    /// Marks a transaction as abandoned.
    ///
    /// Only works on transactions not included in a block and not in the mempool.
    public func abandonTransaction(wallet: String, txid: String) async throws {
        try await sendVoid("abandontransaction", wallet: wallet, params: [.string(txid)])
    }

    /// Rescans the blockchain for wallet transactions.
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - startHeight: Start height (default 0).
    ///   - stopHeight: Stop height (optional, default = chain tip).
    public func rescanBlockchain(wallet: String, startHeight: Int = 0, stopHeight: Int? = nil) async throws -> RescanResult {
        var params: [RPCParam] = [.int(startHeight)]
        if let stop = stopHeight { params.append(.int(stop)) }
        return try await send("rescanblockchain", wallet: wallet, params: params)
    }

    /// Aborts a running wallet rescan.
    public func abortRescan(wallet: String) async throws -> Bool {
        try await send("abortrescan", wallet: wallet)
    }

    // MARK: Sign Message

    /// Signs a message with the private key of an address.
    ///
    /// - Returns: The base64-encoded signature.
    public func signMessage(wallet: String, address: String, message: String) async throws -> String {
        try await send("signmessage", wallet: wallet, params: [.string(address), .string(message)])
    }

    // MARK: Backup & Import

    /// Backs up the wallet to a file.
    public func backupWallet(wallet: String, destination: String) async throws {
        try await sendVoid("backupwallet", wallet: wallet, params: [.string(destination)])
    }

    /// Restores a wallet from a backup file (v24+).
    ///
    /// - Parameters:
    ///   - walletName: The name for the restored wallet.
    ///   - backupFile: Path to the backup file.
    ///   - loadOnStartup: Load on startup (nil = no preference).
    public func restoreWallet(walletName: String, backupFile: String, loadOnStartup: Bool? = nil) async throws -> CreateWalletResult {
        var params: [RPCParam] = [.string(walletName), .string(backupFile)]
        if let load = loadOnStartup { params.append(.bool(load)) } else { params.append(.null) }
        return try await send("restorewallet", params: params)
    }

    /// Imports output descriptors (descriptor wallets only).
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - requests: Array of descriptor import requests.
    /// - Returns: Raw JSON with import results per descriptor.
    public func importDescriptors(wallet: String, requests: [[String: RPCParam]]) async throws -> Data {
        try await callWallet("importdescriptors", wallet: wallet, params: [.encodable(requests)])
    }

    /// Lists all descriptors in the wallet.
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - showPrivate: Include private keys (default false).
    public func listDescriptors(wallet: String, showPrivate: Bool = false) async throws -> Data {
        try await callWallet("listdescriptors", wallet: wallet, params: [.bool(showPrivate)])
    }

    /// Imports funds without rescanning (pruned nodes).
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - rawTransaction: The hex-encoded raw transaction.
    ///   - txOutProof: The hex-encoded proof that the transaction was included in a block.
    public func importPrunedFunds(wallet: String, rawTransaction: String, txOutProof: String) async throws {
        try await sendVoid("importprunedfunds", wallet: wallet, params: [.string(rawTransaction), .string(txOutProof)])
    }

    /// Removes imported funds from the wallet (pruned nodes).
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - txid: The transaction id to remove.
    public func removePrunedFunds(wallet: String, txid: String) async throws {
        try await sendVoid("removeprunedfunds", wallet: wallet, params: [.string(txid)])
    }

    // MARK: Encryption

    /// Unlocks an encrypted wallet for the specified duration.
    ///
    /// - Parameters:
    ///   - wallet: The wallet name.
    ///   - passphrase: The wallet passphrase.
    ///   - timeout: Seconds to keep the wallet unlocked.
    public func walletPassphrase(wallet: String, passphrase: String, timeout: Int) async throws {
        try await sendVoid("walletpassphrase", wallet: wallet, params: [.string(passphrase), .int(timeout)])
    }

    /// Changes the wallet passphrase.
    public func walletPassphraseChange(wallet: String, oldPassphrase: String, newPassphrase: String) async throws {
        try await sendVoid("walletpassphrasechange", wallet: wallet, params: [.string(oldPassphrase), .string(newPassphrase)])
    }

    /// Locks an encrypted wallet.
    public func walletLock(wallet: String) async throws {
        try await sendVoid("walletlock", wallet: wallet)
    }

    /// Encrypts the wallet with a passphrase.
    ///
    /// - Warning: This shuts down the server after encrypting.
    public func encryptWallet(wallet: String, passphrase: String) async throws -> String {
        try await send("encryptwallet", wallet: wallet, params: [.string(passphrase)])
    }
}

#endif
