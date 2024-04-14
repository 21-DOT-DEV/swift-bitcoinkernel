//
//  BlockchainInfo.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

public struct BlockchainInfo: Codable {
    let balance: Double
    let blocks: Int
    let connections: Int
    let proxy: String
    let generate: Bool
    let genproclimit: Int
    let difficulty: Double
}
