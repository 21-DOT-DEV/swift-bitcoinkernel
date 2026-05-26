//
//  CreateWalletResult.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Result of `createwallet` or `loadwallet`.
///
/// - Note: Targets Bitcoin Core v31.x.
public struct CreateWalletResult: Codable, Sendable, Equatable {
    /// The wallet name.
    public let name: String

    /// Warning messages from the operation, if any.
    public let warnings: [String]?

    /// Warning message (older Core versions use single string).
    public let warning: String?
}
