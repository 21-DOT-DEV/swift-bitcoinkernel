//
//  URLSessionConfiguration+Tor.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2022-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

//  Builds a URLSessionConfiguration wired to a SOCKS5 proxy — the
//  plumbing that routes block-source HTTPS requests through the Tor
//  client's local SOCKS listener.
//
//  Uses the modern `ProxyConfiguration` API (iOS 17+/macOS 14+) via the
//  Network framework, which supersedes the CFNetwork
//  `connectionProxyDictionary` keys for new code. The project targets
//  iOS 18 / macOS 15 so the availability floor is comfortably satisfied.
//
//  Note: swift-tor ships its own
//  `URLSessionConfiguration.configuredForTor(socksEndpoint:)` helper,
//  but that one uses the legacy `connectionProxyDictionary` shape. We
//  intentionally diverge to use the modern `ProxyConfiguration` API —
//  hence the distinct factory name `ephemeralProxyConfigurationForTor`.

import Foundation
import Network
import Tor

// MARK: - Tor-routed URLSession configuration

extension URLSessionConfiguration {

    /// Builds an ephemeral session configuration that routes every
    /// request through the supplied SOCKS5 endpoint.
    ///
    /// The returned configuration carries exactly one
    /// `ProxyConfiguration` — a SOCKS5 proxy pointed at `socksEndpoint`.
    /// It is otherwise a vanilla `.ephemeral` configuration (no shared
    /// cookie storage, no disk cache) so per-network-switch proxy
    /// changes don't bleed across runs.
    ///
    /// - Parameter socksEndpoint: The host/port of the local Tor SOCKS5
    ///   listener. Typically `TorViewModel.socksEndpoint` once Tor
    ///   reports `isReady`.
    /// - Returns: A fresh `URLSessionConfiguration`. Callers should
    ///   build a dedicated `URLSession` from it rather than mutate the
    ///   shared one.
    ///
    /// - Note: IPv6 SOCKS endpoints are passed through verbatim;
    ///   `HostPort` does not bracket them. In practice Tor always binds
    ///   the SOCKS listener to an IPv4 loopback, so this has not been a
    ///   concern in either NodeApp or KernelApp.
    static func ephemeralProxyConfigurationForTor(socksEndpoint: HostPort) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral

        let host = NWEndpoint.Host(socksEndpoint.host)
        let port = NWEndpoint.Port(rawValue: UInt16(clamping: socksEndpoint.port)) ?? .any
        let endpoint = NWEndpoint.hostPort(host: host, port: port)

        let proxy = ProxyConfiguration(socksv5Proxy: endpoint)
        configuration.proxyConfigurations = [proxy]

        return configuration
    }
}
