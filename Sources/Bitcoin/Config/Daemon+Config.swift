//
//  Daemon+Config.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

// MARK: - Daemon + BitcoinConfig Bridge

extension Daemon {

    /// Validates a ``BitcoinConfig`` and starts the daemon with its arguments.
    ///
    /// Validation is performed before any daemon process is started. If a
    /// fatal ``ConfigError`` is thrown, the daemon is never started and
    /// `Daemon.waitUntilStopped()` must **not** be called.
    ///
    /// Non-fatal warnings are printed to stdout with an `⚠️` prefix.
    ///
    /// ```swift
    /// let auth = RPCAuth(username: "user", salt: "abc", passwordHMAC: "def")
    /// let config = BitcoinConfig.regtest().rpcAuth(auth).server()
    /// try Daemon.start(with: config)
    /// Daemon.waitUntilStopped()
    /// ```
    ///
    /// - Parameter config: The validated configuration to start the daemon with.
    /// - Throws: ``ConfigError`` if the configuration contains a fatal conflict.
    public static func start<N: BitcoinNetwork>(with config: BitcoinConfig<N>) throws(ConfigError) {
        let warnings = try config.validate()
        for warning in warnings {
            print("⚠️ BitcoinConfig: \(warning)")
        }
        start(config.arguments)
    }

    /// Starts the daemon from a ``BitcoinConfig`` and returns a ready
    /// ``RPCClient``, deriving the endpoint and cookie credentials from the
    /// config so they are supplied exactly once.
    ///
    /// Uses cookie authentication: the config's data directory locates the
    /// `.cookie` Bitcoin Core writes at startup, so no RPC password appears in
    /// caller code. Equivalent to ``start(with:)``, then
    /// ``bootstrap(cookieFile:port:timeout:)``, then
    /// ``RPCClient/init(url:cookieFile:)``.
    ///
    /// One daemon runs per process (see ``Daemon``). To reconfigure, send the
    /// `stop` RPC, call ``waitUntilStopped()``, then start again.
    ///
    /// ```swift
    /// let config = BitcoinConfig.regtest().server().dataDir(dir)
    /// let client = try await Daemon.startAndConnect(with: config)
    /// let info = try await client.getBlockchainInfo()
    /// ```
    ///
    /// - Parameters:
    ///   - config: A config with `.server()` enabled and a `.dataDir(_:)` set.
    ///   - timeout: Maximum time to wait for the RPC server (default 30s).
    /// - Returns: An ``RPCClient`` connected to the daemon.
    /// - Throws: ``DaemonConnectError/missingDataDirectory`` if the config has no
    ///   data directory, ``ConfigError`` for a fatal config conflict, or a
    ///   transport error if the server never becomes ready.
    public static func startAndConnect<N: BitcoinNetwork>(
        with config: BitcoinConfig<N>,
        timeout: Duration = .seconds(30)
    ) async throws -> RPCClient {
        guard let cookieURL = config.cookieURL else {
            throw DaemonConnectError.missingDataDirectory
        }
        try start(with: config)
        try await bootstrap(cookieFile: cookieURL, port: config.resolvedRPCPort, timeout: timeout)
        return RPCClient(url: config.rpcEndpoint, cookieFile: cookieURL)
    }
}

/// An error from ``Daemon/startAndConnect(with:timeout:)`` or
/// ``RPCClient/init(daemon:)``.
public enum DaemonConnectError: Error, CustomStringConvertible, Sendable {
    /// The config has no data directory, so the RPC cookie cannot be located.
    /// Call `.dataDir(_:)` on the config.
    case missingDataDirectory

    public var description: String {
        switch self {
        case .missingDataDirectory:
            return "startAndConnect(with:) needs a data directory to find the RPC cookie; call .dataDir(_:) on the config."
        }
    }
}
