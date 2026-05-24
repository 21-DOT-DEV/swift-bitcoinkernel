//
//  RPCClient+Control.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//


// MARK: - Control RPCs
// https://developer.bitcoin.org/reference/rpc/#control-rpcs

extension RPCClient {

    /// Returns information about memory usage (mode "stats").
    ///
    /// For raw XML malloc info, use `call("getmemoryinfo", params: [.string("mallocinfo")])`.
    public func getMemoryInfo() async throws -> MemoryInfo {
        try await send("getmemoryinfo")
    }

    /// Returns details of the RPC server.
    public func getRPCInfo() async throws -> RPCInfo {
        try await send("getrpcinfo")
    }

    /// Returns help text for a command, or lists all commands if none specified.
    ///
    /// - Parameter command: The RPC command name. Pass `nil` to list all commands.
    public func help(command: String? = nil) async throws -> String {
        var params: [RPCParam] = []
        if let command {
            params.append(.string(command))
        }
        return try await send("help", params: params)
    }

    /// Gets and sets the logging configuration.
    ///
    /// When called without arguments, returns the list of categories with their
    /// current debug logging status. When called with arguments, adds or removes
    /// categories from debug logging.
    ///
    /// - Parameters:
    ///   - include: Categories to add to debug logging.
    ///   - exclude: Categories to remove from debug logging.
    /// - Returns: Dictionary of category names to their enabled status.
    public func logging(include: [String]? = nil, exclude: [String]? = nil) async throws -> [String: Bool] {
        var params: [RPCParam] = []
        if let include {
            params.append(.encodable(include))
            if let exclude {
                params.append(.encodable(exclude))
            }
        }
        return try await send("logging", params: params)
    }

    /// Requests a graceful shutdown of the Bitcoin node.
    ///
    /// - Returns: A string message from the server (e.g. "Bitcoin Core stopping").
    public func stop() async throws -> String {
        try await send("stop")
    }

    /// Returns the total uptime of the server in seconds.
    public func uptime() async throws -> Int {
        try await send("uptime")
    }
}
