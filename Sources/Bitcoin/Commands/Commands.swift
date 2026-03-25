//
//  Commands.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2024 Timechain Software Initiative 
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// An enumeration of supported Bitcoin JSON-RPC commands.
///
/// This enum provides a type-safe way to specify which command
/// should be sent to the Bitcoin node. The raw values are lowercase
/// to match the Bitcoin Core RPC command format.
public enum Commands: String {
    /// Get the hash of the best (tip) block in the most-work fully-validated chain.
    case getBestBlockHash = "getbestblockhash"
    
    /// Get the current blockchain information.
    case getBlockchainInfo = "getblockchaininfo"
    
    /// Get detailed information about an in-wallet transaction.
    case getTransaction = "gettransaction"
    
    /// Creates a transaction in the Partially Signed Transaction format.
    case createPSBT = "createpsbt"
    
    /// Returns the height of the most-work fully-validated chain.
    case getBlockCount = "getblockcount"
    
    /// Get a block in the blockchain by hash.
    case getBlock = "getblock"

    /// Request a graceful shutdown of the server.
    case stop = "stop"
    
    // Add more commands as needed, ensuring the raw value is lowercase
}
