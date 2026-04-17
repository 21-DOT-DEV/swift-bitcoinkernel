//
//  TorViewModelTests.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
@testable import NodeApp

// MARK: - TorDisplayState Tests

@Suite("TorDisplayState")
struct TorDisplayStateTests {

    @Test("Raw values match expected display strings")
    func rawValues() {
        #expect(TorDisplayState.disabled.rawValue == "Disabled")
        #expect(TorDisplayState.starting.rawValue == "Starting")
        #expect(TorDisplayState.running.rawValue  == "Running")
        #expect(TorDisplayState.stopping.rawValue == "Stopping")
        #expect(TorDisplayState.failed.rawValue   == "Failed")
    }

    @Test("TorDisplayState conforms to Sendable")
    func sendableConformance() {
        let state: any Sendable = TorDisplayState.running
        #expect(state is TorDisplayState)
    }
}

// MARK: - TorViewModel State Tests

@Suite("TorViewModel")
@MainActor
struct TorViewModelTests {

    @Test("Initial state is disabled")
    func initialState() {
        let vm = TorViewModel()
        #expect(vm.displayState == .disabled)
        #expect(vm.bootstrapProgress == 0)
        #expect(vm.bootstrapSummary == "")
        #expect(vm.socksEndpoint == nil)
    }

    @Test("isReady is false when disabled")
    func notReadyWhenDisabled() {
        let vm = TorViewModel()
        #expect(!vm.isReady)
    }

    @Test("proxyAddress is nil when no endpoint")
    func proxyAddressNilWithoutEndpoint() {
        let vm = TorViewModel()
        #expect(vm.proxyAddress == nil)
    }
}
