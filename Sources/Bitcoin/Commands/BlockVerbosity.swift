//
//  BlockVerbosity.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2024 Timechain Software Initiative 
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Represents the verbosity levels for the getblock command.
public enum BlockVerbosity: Int {
    /// Returns a hex-encoded block.
    case raw = 0
    
    /// Returns a block with transaction IDs.
    case json = 1
    
    /// Returns a block with full transaction details.
    case jsonWithTransactions = 2
}