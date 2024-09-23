//
//  Transaction.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2024 Timechain Software Initiative 
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Represents a Bitcoin transaction.
public struct Transaction: Codable {
    public let txid: String
    public let hash: String
    public let version: Int
    public let size: Int
    public let vsize: Int
    public let weight: Int
    public let locktime: Int
    // Add more fields as needed
}