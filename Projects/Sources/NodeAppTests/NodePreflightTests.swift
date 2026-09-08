//
//  NodePreflightTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
@testable import NodeApp

@Suite("Node preflight conditions")
struct NodePreflightTests {

    private let oneGB: Int64 = 1_073_741_824

    @Test("a healthy device is allowed to start the node")
    func healthyDeviceProceeds() {
        #expect(NodePreflight.refusal(for: .init(freeDiskBytes: 8 * oneGB)) == nil)
    }

    @Test("unreadable files stop the run")
    func unreadableFiles() {
        #expect(
            NodePreflight.refusal(for: .init(filesReadable: false, freeDiskBytes: 8 * oneGB))
                == .filesNotReadable)
    }

    @Test("too little free space stops the run and reports how much is left")
    func notEnoughDisk() {
        let free = oneGB / 2
        #expect(
            NodePreflight.refusal(for: .init(freeDiskBytes: free))
                == .notEnoughDisk(freeBytes: free))
    }

    @Test("free space exactly at the floor is allowed; one byte under is not")
    func diskBoundary() {
        #expect(NodePreflight.refusal(for: .init(freeDiskBytes: oneGB)) == nil)
        #expect(
            NodePreflight.refusal(for: .init(freeDiskBytes: oneGB - 1))
                == .notEnoughDisk(freeBytes: oneGB - 1))
    }

    @Test("unknown free space is not treated as too little")
    func unknownDiskProceeds() {
        // Refusing on a failed reading would ground every run on a device whose
        // free space cannot be queried.
        #expect(NodePreflight.refusal(for: .init(freeDiskBytes: nil)) == nil)
    }

    @Test("a metered network stops the run")
    func meteredNetwork() {
        #expect(
            NodePreflight.refusal(for: .init(networkIsMetered: true, freeDiskBytes: 8 * oneGB))
                == .meteredNetwork)
    }

    @Test("a data-restricted network stops the run even when it is not metered")
    func dataRestrictedNetwork() {
        // Low Data Mode on home wireless is restricted but not metered; either one
        // alone must stop a multi-gigabyte sync.
        #expect(
            NodePreflight.refusal(
                for: .init(networkIsDataRestricted: true, freeDiskBytes: 8 * oneGB))
                == .dataRestrictedNetwork)
    }

    @Test("network cost is reported ahead of heat and battery saver")
    func networkOutranksHeatAndBattery() {
        // Spending someone's data allowance costs money; heat and battery do not.
        let conditions = NodePreflight.DeviceConditions(
            lowPowerModeEnabled: true, networkIsMetered: true, overheating: true,
            freeDiskBytes: 8 * oneGB)
        #expect(NodePreflight.refusal(for: conditions) == .meteredNetwork)
    }

    @Test("an overheating device stops the run")
    func overheating() {
        #expect(
            NodePreflight.refusal(for: .init(overheating: true, freeDiskBytes: 8 * oneGB))
                == .overheating)
    }

    @Test("battery saver stops the run")
    func lowPowerMode() {
        #expect(
            NodePreflight.refusal(
                for: .init(lowPowerModeEnabled: true, freeDiskBytes: 8 * oneGB))
                == .lowPowerMode)
    }

    @Test("the most fundamental reason is reported when several apply")
    func refusalPriority() {
        // Full order: unreadable files, disk, metered, data-restricted, heat, saver.
        // Each step removes the winning condition and expects the next one down.
        var conditions = NodePreflight.DeviceConditions(
            filesReadable: false, lowPowerModeEnabled: true, networkIsMetered: true,
            networkIsDataRestricted: true, overheating: true, freeDiskBytes: 0)
        #expect(NodePreflight.refusal(for: conditions) == .filesNotReadable)

        conditions.filesReadable = true
        #expect(NodePreflight.refusal(for: conditions) == .notEnoughDisk(freeBytes: 0))

        conditions.freeDiskBytes = 8 * oneGB
        #expect(NodePreflight.refusal(for: conditions) == .meteredNetwork)

        conditions.networkIsMetered = false
        #expect(NodePreflight.refusal(for: conditions) == .dataRestrictedNetwork)

        conditions.networkIsDataRestricted = false
        #expect(NodePreflight.refusal(for: conditions) == .overheating)

        conditions.overheating = false
        #expect(NodePreflight.refusal(for: conditions) == .lowPowerMode)

        conditions.lowPowerModeEnabled = false
        #expect(NodePreflight.refusal(for: conditions) == nil)
    }

    @Test("the disk floor is a parameter, so a caller can tighten or relax it")
    func customDiskFloor() {
        let conditions = NodePreflight.DeviceConditions(freeDiskBytes: 2 * oneGB)
        #expect(NodePreflight.refusal(for: conditions, minimumFreeDiskBytes: oneGB) == nil)
        #expect(
            NodePreflight.refusal(for: conditions, minimumFreeDiskBytes: 4 * oneGB)
                == .notEnoughDisk(freeBytes: 2 * oneGB))
    }

    @Test("every reason has wording")
    func messages() {
        #expect(NodePreflight.Refusal.filesNotReadable.message.isEmpty == false)
        #expect(NodePreflight.Refusal.meteredNetwork.message.isEmpty == false)
        #expect(NodePreflight.Refusal.dataRestrictedNetwork.message.isEmpty == false)
        #expect(NodePreflight.Refusal.overheating.message.isEmpty == false)
        #expect(NodePreflight.Refusal.lowPowerMode.message.isEmpty == false)
        #expect(NodePreflight.Refusal.notEnoughDisk(freeBytes: oneGB / 2).message.isEmpty == false)
    }

    @Test("the metered-network wording covers a shared phone link, not just cellular")
    func meteredWordingCoversHotspot() {
        // The condition it reports also covers a link shared from another phone, so
        // naming only cellular would be false in that case.
        let message = NodePreflight.Refusal.meteredNetwork.message
        #expect(message.contains("metered"))
        #expect(message.contains("shared from another phone"))
    }

    @Test("the space left is rendered by the platform, so it never overstates what is free")
    func diskWordingUsesPlatformFormatting() {
        // Regression: this text was hand-built, dividing by 1024³ while labelling the
        // result "GB" (the smaller decimal unit) and formatting to one decimal place,
        // which rounded *up*. One byte under the floor printed as "1.0 GB is too
        // little" — a message contradicting itself. Asserting against the platform's
        // own output pins the fix without hardcoding wording that varies by language.
        for bytes: Int64 in [0, 1, oneGB / 2, oneGB - 1] {
            let expected = bytes.formatted(.byteCount(style: .file))
            let message = NodePreflight.Refusal.notEnoughDisk(freeBytes: bytes).message
            #expect(message.contains(expected))
        }
        // The specific case that used to lie: one byte under the floor must not be
        // reported as the round figure that would look like it met the floor.
        let atThreshold = NodePreflight.Refusal.notEnoughDisk(freeBytes: oneGB - 1).message
        #expect(atThreshold.contains("1.0 GB") == false)
    }
}
