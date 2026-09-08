//
//  NodeAutomationTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
@testable import NodeApp

@Suite("Node Automation decisions")
struct NodeAutomationTests {

    // MARK: - step(...)

    @Test("a node that is not stopped is reported, never restarted")
    func reportsExistingNode() {
        #expect(
            NodeAutomation.step(nodeIsStopped: false, privacyEnabled: false, privacyReady: false)
                == .reportExistingNode)
        // Even with the privacy network on and ready, a running node is left alone.
        #expect(
            NodeAutomation.step(nodeIsStopped: false, privacyEnabled: true, privacyReady: true)
                == .reportExistingNode)
    }

    @Test("with the privacy network off, a stopped node starts")
    func startsWithoutPrivacy() {
        #expect(
            NodeAutomation.step(nodeIsStopped: true, privacyEnabled: false, privacyReady: false)
                == .startNode)
    }

    @Test("with the privacy network on and ready, a stopped node starts")
    func startsWhenPrivacyReady() {
        #expect(
            NodeAutomation.step(nodeIsStopped: true, privacyEnabled: true, privacyReady: true)
                == .startNode)
    }

    @Test("with the privacy network on but not ready, the run waits instead of starting")
    func waitsForPrivacy() {
        #expect(
            NodeAutomation.step(nodeIsStopped: true, privacyEnabled: true, privacyReady: false)
                == .waitForPrivateNetwork)
    }

    // MARK: - startArguments(...)

    @Test("arguments pass through when the privacy network is off")
    func argumentsWithoutPrivacy() throws {
        let args = try NodeAutomation.startArguments(
            privacyEnabled: false, proxyAddress: nil, build: { _ in ["-noproxy"] })
        #expect(args == ["-noproxy"])
    }

    @Test("the proxy address is handed to the builder when the privacy network is ready")
    func argumentsWithPrivacyReady() throws {
        var seenProxy: String? = "unset"
        let args = try NodeAutomation.startArguments(
            privacyEnabled: true, proxyAddress: "127.0.0.1:9050",
            build: { proxy in
                seenProxy = proxy
                return ["-proxy=\(proxy ?? "")"]
            })
        #expect(seenProxy == "127.0.0.1:9050")
        #expect(args == ["-proxy=127.0.0.1:9050"])
    }

    @Test("starting is refused, and the builder never runs, when privacy is on but has no proxy")
    func refusesWithoutProxy() {
        var builderRan = false
        #expect(throws: NodeAutomation.StartRefusal.privateNetworkNotReady) {
            _ = try NodeAutomation.startArguments(
                privacyEnabled: true, proxyAddress: nil,
                build: { _ in
                    builderRan = true
                    return ["-should-not-build"]
                })
        }
        #expect(builderRan == false)
    }

    @Test("starting is refused, and the builder never runs, when the proxy is present but empty")
    func refusesEmptyProxy() {
        var builderRan = false
        #expect(throws: NodeAutomation.StartRefusal.privateNetworkNotReady) {
            _ = try NodeAutomation.startArguments(
                privacyEnabled: true, proxyAddress: "",
                build: { _ in
                    builderRan = true
                    return ["-should-not-build"]
                })
        }
        #expect(builderRan == false)
    }

    @Test("starting is refused when the proxy is only whitespace")
    func refusesBlankProxy() {
        #expect(throws: NodeAutomation.StartRefusal.privateNetworkNotReady) {
            _ = try NodeAutomation.startArguments(
                privacyEnabled: true, proxyAddress: "   ",
                build: { _ in ["-should-not-build"] })
        }
    }

    @Test("an empty proxy is passed through only when the privacy network is off")
    func emptyProxyAllowedWithoutPrivacy() throws {
        let args = try NodeAutomation.startArguments(
            privacyEnabled: false, proxyAddress: "",
            build: { _ in ["-noproxy"] })
        #expect(args == ["-noproxy"])
    }

    @Test("a proxy with surrounding whitespace is trimmed before it reaches the builder")
    func trimsProxyBeforeBuilding() throws {
        var seenProxy: String? = "unset"
        let args = try NodeAutomation.startArguments(
            privacyEnabled: true, proxyAddress: "  127.0.0.1:9050  ",
            build: { proxy in
                seenProxy = proxy
                return ["-proxy=\(proxy ?? "")"]
            })
        #expect(seenProxy == "127.0.0.1:9050")
        #expect(args == ["-proxy=127.0.0.1:9050"])
    }
}
