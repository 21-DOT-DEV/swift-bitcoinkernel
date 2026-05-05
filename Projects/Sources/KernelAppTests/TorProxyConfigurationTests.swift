//
//  TorProxyConfigurationTests.swift
//  21-DOT-DEV/Bitcoin
//
//  Verifies the `URLSessionConfiguration.ephemeralProxyConfigurationForTor(socksEndpoint:)`
//  helper attaches a proxy configuration to an otherwise clean session.
//  The modern `ProxyConfiguration` struct is intentionally opaque — its
//  internals aren't directly assertable — so the checks here are
//  black-box: did the helper produce a proxy, and did it survive attachment
//  to a URLSessionConfiguration? Round-trip through the factory in
//  `KernelAppViewModelTorTests` exercises the end-to-end `HostPort`
//  plumbing.
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import Testing
import Tor
@testable import KernelApp

@Suite("URLSessionConfiguration+Tor")
struct TorProxyConfigurationTests {

    @Test("ephemeralProxyConfigurationForTor attaches exactly one proxy configuration")
    func attachesOneProxy() {
        let endpoint = HostPort.localhost(9050)
        let config = URLSessionConfiguration.ephemeralProxyConfigurationForTor(socksEndpoint: endpoint)

        #expect(config.proxyConfigurations.count == 1)
    }

    @Test("ephemeralProxyConfigurationForTor has no on-disk URL cache")
    func isEphemeral() {
        let endpoint = HostPort.localhost(9050)
        let config = URLSessionConfiguration.ephemeralProxyConfigurationForTor(socksEndpoint: endpoint)

        // Ephemeral configurations keep an in-memory cookie jar + cache,
        // but never persist to disk. The zero-disk-capacity invariant
        // is the durable contract; exact `nil` identity of
        // `httpCookieStorage`/`urlCache` is an implementation detail
        // that has flipped across SDK revisions.
        #expect(config.urlCache?.diskCapacity == 0,
                "ephemeral configuration must not back cache with disk storage")
    }

    @Test("ephemeralProxyConfigurationForTor accepts arbitrary port values within UInt16 range")
    func acceptsHighPort() {
        let config = URLSessionConfiguration.ephemeralProxyConfigurationForTor(
            socksEndpoint: HostPort(host: "127.0.0.1", port: 43210)
        )
        #expect(config.proxyConfigurations.count == 1)
    }

    @Test("ephemeralProxyConfigurationForTor is usable as input to URLSession(configuration:)")
    func buildsLiveSession() {
        let config = URLSessionConfiguration.ephemeralProxyConfigurationForTor(
            socksEndpoint: HostPort.localhost(9050)
        )
        // Constructing the session doesn't reach the network; it's a
        // smoke test that the configuration is well-formed enough for
        // URLSession to accept without trapping.
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        #expect(session.configuration.proxyConfigurations.count == 1)
    }
}
