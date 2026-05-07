//
//  Daemon+Config.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

// MARK: - Daemon + BitcoinConfig Bridge

extension Daemon {

    /// Validates a `BitcoinConfig` and starts the daemon with its arguments.
    ///
    /// Validation is performed before any daemon process is started. If a
    /// fatal `ConfigError` is thrown, the daemon is never started and
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
    /// - Throws: `ConfigError` if the configuration contains a fatal conflict.
    public static func start<N: BitcoinNetwork>(with config: BitcoinConfig<N>) throws(ConfigError) {
        let warnings = try config.validate()
        for warning in warnings {
            print("⚠️ BitcoinConfig: \(warning)")
        }
        start(config.arguments)
    }
}
