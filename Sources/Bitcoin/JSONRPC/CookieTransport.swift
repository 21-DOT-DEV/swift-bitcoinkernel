//
//  CookieTransport.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2024 Timechain Software Initiative
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// HTTP transport that reads credentials from a Bitcoin Core `.cookie` file
/// on each call, enabling lazy authentication without hardcoded credentials.
///
/// The cookie file is written by Bitcoin Core at startup and deleted on
/// shutdown. Its format is `__cookie__:<random-hex>`. Credentials change on
/// every daemon restart, so this transport reads them fresh per-request.
///
/// Conforms to ``WalletCapableTransport`` because it delegates to
/// ``HTTPTransport``, which supports wallet path scoping.
public struct CookieTransport: WalletCapableTransport {
    private let url: URL
    private let cookieFile: URL
    private let session: URLSession

    /// Creates a cookie-authenticated HTTP transport.
    ///
    /// - Parameters:
    ///   - url: The RPC endpoint URL (e.g., `http://127.0.0.1:8332`).
    ///   - cookieFile: File URL to the `.cookie` file.
    ///   - session: The URL session to use. Defaults to `.shared`.
    public init(url: URL, cookieFile: URL, session: URLSession = .shared) {
        self.url = url
        self.cookieFile = cookieFile
        self.session = session
    }

    public func send(_ request: JSONRPCRequest, path: String?) async throws -> Data {
        let cookie = try String(contentsOf: cookieFile, encoding: .utf8)
        let (username, password) = try Daemon.parseCookie(cookie)
        let http = HTTPTransport(url: url, username: username, password: password, session: session)
        return try await http.send(request, path: path)
    }
}
