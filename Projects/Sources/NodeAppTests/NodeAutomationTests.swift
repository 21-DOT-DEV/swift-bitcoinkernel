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
import Foundation
import Bitcoin
@testable import NodeApp

@Suite("Node Automation decisions")
struct NodeAutomationTests {

    // MARK: - step(...)

    @Test("a node that is running is reported, never restarted")
    func reportsExistingNode() {
        #expect(
            NodeAutomation.step(nodeState: .running, privacyEnabled: false, privacyReady: false)
                == .reportExistingNode)
        // Even with the privacy network on and ready, a running node is left alone.
        #expect(
            NodeAutomation.step(nodeState: .running, privacyEnabled: true, privacyReady: true)
                == .reportExistingNode)
    }

    @Test("a node still shutting down is reported like a running one")
    func reportsStoppingNode() {
        // It cannot be started (`start()` refuses anything but `.stopped`), and the
        // read path's answer checks land it on `noAnswer` if it finishes stopping
        // mid-question — so it is read and left alone like a running one.
        #expect(
            NodeAutomation.step(nodeState: .stopping, privacyEnabled: false, privacyReady: false)
                == .reportExistingNode)
        // The privacy gate does not reroute it either — a node on its way down is
        // read like a running one whatever the network preference says.
        #expect(
            NodeAutomation.step(nodeState: .stopping, privacyEnabled: true, privacyReady: false)
                == .reportExistingNode)
    }

    @Test("a node still coming up is waited on, not read once and not restarted")
    func waitsForStartingNode() {
        // Mid-startup cannot answer until its block index loads — minutes on a
        // locked phone — so a single read would almost certainly end in
        // `noAnswer`; and it cannot be started again either.
        #expect(
            NodeAutomation.step(nodeState: .starting, privacyEnabled: false, privacyReady: false)
                == .waitForStartingNode)
        // The privacy gate does not apply: whoever started the node already chose
        // its connection, and the run cannot undo that by declining to wait.
        #expect(
            NodeAutomation.step(nodeState: .starting, privacyEnabled: true, privacyReady: false)
                == .waitForStartingNode)
    }

    @Test("with the privacy network off, a stopped node starts")
    func startsWithoutPrivacy() {
        #expect(
            NodeAutomation.step(nodeState: .stopped, privacyEnabled: false, privacyReady: false)
                == .startNode)
    }

    @Test("with the privacy network on and ready, a stopped node starts")
    func startsWhenPrivacyReady() {
        #expect(
            NodeAutomation.step(nodeState: .stopped, privacyEnabled: true, privacyReady: true)
                == .startNode)
    }

    @Test("with the privacy network on but not ready, the run waits instead of starting")
    func waitsForPrivacy() {
        #expect(
            NodeAutomation.step(nodeState: .stopped, privacyEnabled: true, privacyReady: false)
                == .waitForPrivateNetwork)
    }

    // MARK: - consultsDeviceConditions(...)

    @Test("only steps that start something are weighed against device conditions")
    func conditionsGateStartingNotReporting() {
        #expect(NodeAutomation.consultsDeviceConditions(for: .startNode))
        #expect(NodeAutomation.consultsDeviceConditions(for: .waitForPrivateNetwork))
        // Reading a running node or waiting on a starting one spends nothing the
        // conditions protect — gating them would report "not started" about a
        // node that is.
        #expect(NodeAutomation.consultsDeviceConditions(for: .reportExistingNode) == false)
        #expect(NodeAutomation.consultsDeviceConditions(for: .waitForStartingNode) == false)
    }

    // MARK: - startArguments(...)

    @Test("arguments pass through when the privacy network is off")
    func argumentsWithoutPrivacy() throws {
        let args = try NodeAutomation.startArguments(
            snapshotEnabled: false, liveEnabled: false,
            proxyAddress: nil, build: { _ in ["-noproxy"] })
        #expect(args == ["-noproxy"])
    }

    @Test("the proxy address is handed to the builder when the privacy network is ready")
    func argumentsWithPrivacyReady() throws {
        var seenProxy: String? = "unset"
        let args = try NodeAutomation.startArguments(
            snapshotEnabled: true, liveEnabled: true, proxyAddress: "127.0.0.1:9050",
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
                snapshotEnabled: true, liveEnabled: true, proxyAddress: nil,
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
                snapshotEnabled: true, liveEnabled: true, proxyAddress: "",
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
                snapshotEnabled: true, liveEnabled: true, proxyAddress: "   ",
                build: { _ in ["-should-not-build"] })
        }
    }

    @Test("an empty proxy is passed through only when the privacy network is off")
    func emptyProxyAllowedWithoutPrivacy() throws {
        let args = try NodeAutomation.startArguments(
            snapshotEnabled: false, liveEnabled: false,
            proxyAddress: "", build: { _ in ["-noproxy"] })
        #expect(args == ["-noproxy"])
    }

    @Test("a proxy with surrounding whitespace is trimmed before it reaches the builder")
    func trimsProxyBeforeBuilding() throws {
        var seenProxy: String? = "unset"
        let args = try NodeAutomation.startArguments(
            snapshotEnabled: true, liveEnabled: true,
            proxyAddress: "  127.0.0.1:9050  ",
            build: { proxy in
                seenProxy = proxy
                return ["-proxy=\(proxy ?? "")"]
            })
        #expect(seenProxy == "127.0.0.1:9050")
        #expect(args == ["-proxy=127.0.0.1:9050"])
    }

    @Test("a launch that began private declines when the setting was turned off mid-flight, even with a live proxy")
    func turnedOffMidFlightRefuses() {
        var builderRan = false
        #expect(throws: NodeAutomation.StartRefusal.privateNetworkTurnedOff) {
            _ = try NodeAutomation.startArguments(
                snapshotEnabled: true, liveEnabled: false,
                proxyAddress: "127.0.0.1:9050",
                build: { _ in
                    builderRan = true
                    return ["-should-not-build"]
                })
        }
        #expect(builderRan == false)
    }

    @Test("the turned-off refusal outranks a missing proxy")
    func turnedOffOutranksMissingProxy() {
        #expect(throws: NodeAutomation.StartRefusal.privateNetworkTurnedOff) {
            _ = try NodeAutomation.startArguments(
                snapshotEnabled: true, liveEnabled: false,
                proxyAddress: nil,
                build: { _ in ["-should-not-build"] })
        }
    }

    @Test("a setting switched on mid-flight still builds with the proxy it now requires")
    func liveOnFlipBuildsPrivate() throws {
        let args = try NodeAutomation.startArguments(
            snapshotEnabled: false, liveEnabled: true,
            proxyAddress: "127.0.0.1:9050",
            build: { ["-proxy=\($0 ?? "")"] })
        #expect(args == ["-proxy=127.0.0.1:9050"])
    }

    @Test("a setting switched on mid-flight refuses when no proxy is usable")
    func liveOnFlipRefusesWithoutProxy() {
        #expect(throws: NodeAutomation.StartRefusal.privateNetworkNotReady) {
            _ = try NodeAutomation.startArguments(
                snapshotEnabled: false, liveEnabled: true,
                proxyAddress: nil,
                build: { _ in ["-should-not-build"] })
        }
    }

    // MARK: - requiresPrivateNetwork(...)

    @Test("privacy is required when either the snapshot or the live setting says so")
    func privacyRequiredFailsClosed() {
        // The launch boundary's one live read: a toggle flipped *on* mid-run
        // engages the floor even though the run's snapshot never saw it, and a
        // snapshot that required privacy keeps it if the toggle was flipped
        // *off* — a decline is recoverable, a leak is not (ADR 0006).
        #expect(NodeAutomation.requiresPrivateNetwork(
            snapshotEnabled: true, liveEnabled: true))
        #expect(NodeAutomation.requiresPrivateNetwork(
            snapshotEnabled: true, liveEnabled: false))
        #expect(NodeAutomation.requiresPrivateNetwork(
            snapshotEnabled: false, liveEnabled: true))
        #expect(NodeAutomation.requiresPrivateNetwork(
            snapshotEnabled: false, liveEnabled: false) == false)
    }

    @Test("the refusal picks its case from the live setting, not the snapshot")
    func startRefusalPicksByLiveSetting() {
        // Still on → the network is genuinely on its way up; off → nothing is
        // being established, and the message must not claim it is.
        #expect(
            NodeAutomation.StartRefusal(stillEnabled: true) == .privateNetworkNotReady)
        #expect(
            NodeAutomation.StartRefusal(stillEnabled: false) == .privateNetworkTurnedOff)
        // The switched-off sentence must not claim the network "is being
        // established" — nothing is. The messages are deferred templates, so a
        // test resolves them the way the system's dialog would.
        #expect(
            String(localized: NodeAutomation.StartRefusal.privateNetworkTurnedOff.message)
                .contains("being established") == false)
    }

    @Test("the private-network refusal carries the sentence both declining paths share")
    func startRefusalMessage() {
        // Two paths decline for this reason — the deliberate wait-for-it step and
        // the start that finds it gone at the last moment — so the sentence lives
        // on the refusal itself. Pinned here because wording that drifted between
        // them would tell the person two different stories about the same thing.
        let message = String(
            localized: NodeAutomation.StartRefusal.privateNetworkNotReady.message)
        #expect(message.contains("private network was not ready"))
        #expect(message.contains("being established"))
    }

    // MARK: - Turning readings into a report

    private func reading(
        _ chain: String, _ height: Int, behind: Int = 0,
        isInitialBlockDownload: Bool = false,
        tipTime: Date? = nil
    ) -> NodeAutomation.LiveReading {
        // No tip given lands at `watchNow` — fresh — so a bare reading is the
        // gate's all-clear baseline and staleness is always an explicit choice.
        NodeAutomation.LiveReading(
            chain: chain, height: height, blocksBehind: behind,
            isInitialBlockDownload: isInitialBlockDownload, headers: height + behind,
            tipTime: tipTime ?? watchNow)
    }

    private func baseline(_ chain: String, _ height: Int) -> NodeAutomation.TipBaseline {
        NodeAutomation.TipBaseline(chain: chain, height: height)
    }

    @Test("a chain answer maps every field the watch needs from one reading")
    func readingMapsAllFields() throws {
        let info = try JSONDecoder().decode(
            BlockchainInfo.self, from: Data(Self.infoJSON.utf8))
        let reading = NodeAutomation.reading(from: info)
        #expect(reading.chain == "signet")
        #expect(reading.height == 100)
        #expect(reading.headers == 200)
        #expect(reading.blocksBehind == 100)
        #expect(reading.isInitialBlockDownload == true)
        #expect(reading.tipTime == Date(timeIntervalSince1970: 1_713_300_000))
    }

    @Test("a peer's evidence carries its announced best-known height and resolved kind")
    func peerEvidenceMapsFields() throws {
        let peer = try Self.decodePeer(connectionType: "outbound-full-relay", inbound: false)
        let evidence = NodeAutomation.PeerEvidence(peer)
        #expect(evidence.syncedHeaders == 876_000)
        #expect(evidence.connectionType == .outboundFullRelay)
    }

    @Test("a missing connection type falls back to direction — inbound resolves to the real kind")
    func peerEvidenceInboundFallback() throws {
        let peer = try Self.decodePeer(connectionType: nil, inbound: true)
        #expect(NodeAutomation.PeerEvidence(peer).connectionType == .inbound)
    }

    @Test("a missing connection type on an outbound peer resolves to no countable kind")
    func peerEvidenceUnresolvedOutboundFailsClosed() throws {
        let peer = try Self.decodePeer(connectionType: nil, inbound: false)
        let resolved = NodeAutomation.PeerEvidence(peer).connectionType
        // The generic "outbound" an absent field yields is a real resolution, but
        // it equals neither kind the catch-up proof counts — a peer the node
        // cannot classify can never be mistaken for block-serving.
        #expect(resolved == .unresolvedOutbound)
        #expect(resolved != .outboundFullRelay && resolved != .blockRelayOnly)
    }

    @Test("the connection vocabulary names every kind the wire produces")
    func connectionTypeVocabulary() throws {
        // All seven values `ConnectionTypeAsString` emits — this fork's
        // `private-broadcast` included — resolve to their named constants.
        for (wire, kind) in [
            ("inbound", .inbound), ("outbound-full-relay", .outboundFullRelay),
            ("block-relay-only", .blockRelayOnly), ("manual", .manual),
            ("feeler", .feeler), ("addr-fetch", .addrFetch),
            ("private-broadcast", .privateBroadcast),
        ] as [(String, NodeAutomation.PeerEvidence.ConnectionType)] {
            let peer = try Self.decodePeer(connectionType: wire, inbound: wire == "inbound")
            #expect(NodeAutomation.PeerEvidence(peer).connectionType == kind)
        }
    }

    /// A `getblockchaininfo` answer mid-IBD — every field the decoder requires,
    /// the four the watch reads included.
    private static let infoJSON = """
    {
      "chain": "signet", "blocks": 100, "headers": 200,
      "bestblockhash": "0000000000000000000000000000000000000000000000000000000000000abc",
      "difficulty": 1.0, "time": 1713300000, "mediantime": 1713299990,
      "verificationprogress": 0.5, "initialblockdownload": true,
      "chainwork": "0000000000000000000000000000000000000000000000000000000000000192",
      "size_on_disk": 12345, "pruned": false, "warnings": []
    }
    """

    /// A `getpeerinfo` row carrying the two fields `PeerEvidence` reads — the
    /// rest exist only because the decoder requires them.
    private static func decodePeer(
        connectionType: String?, inbound: Bool, syncedHeaders: Int = 876_000
    ) throws -> PeerInfo {
        let connField = connectionType.map { "\"connection_type\":\"\($0)\"," } ?? ""
        return try JSONDecoder().decode(
            PeerInfo.self,
            from: Data(
                """
                {"id":0,"addr":"10.0.0.1:8333","services":"0000000000000409","relaytxes":true,
                 "lastsend":1713300000,"lastrecv":1713300000,"bytessent":1000,"bytesrecv":2000,
                 "conntime":1713200000,"timeoffset":0,"version":70016,"subver":"/Satoshi:31.0.0/",
                 \(connField)"inbound":\(inbound),"synced_headers":\(syncedHeaders),"synced_blocks":876000}
                """.utf8))
    }

    @Test("blocks since a baseline is the difference between two readings")
    func blocksSince() {
        #expect(
            NodeAutomation.blocksSince(previous: baseline("main", 100), to: reading("main", 142)) == 42)
    }

    @Test("blocks since a baseline is unknown when either reading is missing")
    func blocksSinceMissing() {
        #expect(NodeAutomation.blocksSince(previous: nil, to: reading("main", 142)) == nil)
        #expect(NodeAutomation.blocksSince(previous: baseline("main", 100), to: nil) == nil)
    }

    @Test("blocks since a baseline is unknown across different chains, never a nonsense number")
    func blocksSinceAcrossChains() {
        // Subtracting a test-chain height from a main-chain one would produce a
        // confident-looking lie.
        #expect(
            NodeAutomation.blocksSince(previous: baseline("test", 10), to: reading("main", 900_000))
                == nil)
    }

    @Test("a height that went backwards reports no gain rather than a negative one")
    func blocksSinceNeverNegative() {
        #expect(
            NodeAutomation.blocksSince(previous: baseline("main", 200), to: reading("main", 150)) == 0)
    }

    @Test("a declined run reports its reason as the whole message")
    func summaryDeclined() {
        // The summaries are deferred templates — `String(localized:)` resolves
        // one the way the system's dialog would.
        let text = String(
            localized: NodeAutomation.summary(
                outcome: .declined, syncEnding: .notMeasured,
                chain: "main", height: 5, blocksBehind: nil,
                blocksSinceLastCheck: nil, declinedReason: "Low Power Mode is on."))
        #expect(text == "Low Power Mode is on.")
    }

    @Test("a run that found the node still coming up says nothing was measured")
    func summaryDidNotComeUp() {
        let text = String(
            localized: NodeAutomation.summary(
                outcome: .didNotComeUp, syncEnding: .notMeasured,
                chain: "main", height: 5, blocksBehind: nil,
                blocksSinceLastCheck: nil, declinedReason: nil))
        #expect(text.contains("had not come up"))
        #expect(text.contains("nothing was measured"))
        // It must not say who started the node — on this path it may already have
        // been coming up before the run began.
        #expect(text.contains("started") == false)
    }

    @Test("a run that got no usable answer says nothing was measured")
    func summaryNoAnswer() {
        // Covers both ways a run ends here — a node that never answered, and an
        // answer discarded because the node was stopped or the run ended while the
        // question was in flight. Either way, nothing usable was measured.
        let text = String(
            localized: NodeAutomation.summary(
                outcome: .noAnswer, syncEnding: .notMeasured,
                chain: "main", height: 5, blocksBehind: nil,
                blocksSinceLastCheck: nil, declinedReason: nil))
        #expect(text.contains("did not answer"))
        #expect(text.contains("nothing was measured"))
        // It must not imply the node was started — on this path it may already have
        // been running.
        #expect(text.contains("started") == false)
    }

    @Test("a started run names the chain, the height, and what arrived since")
    func summaryStarted() {
        let text = String(
            localized: NodeAutomation.summary(
                outcome: .started, syncEnding: .notMeasured,
                chain: "main", height: 900_000, blocksBehind: 12,
                blocksSinceLastCheck: 3, declinedReason: nil))
        // The node's "main" wire name is mapped to the display name before a
        // person reads it.
        #expect(text.contains("Mainnet"))
        // The count interpolates as a raw Int (%lld), which the resolver renders
        // with the locale's digit grouping — "900,000" in en_US — so asserting
        // the grouped figure still fails if the code ever strings the number
        // through a fixed-locale formatter instead.
        #expect(text.contains(900_000.formatted()))
        #expect(text.contains("\(12.formatted()) behind"))
        #expect(text.contains("\(3.formatted()) new blocks"))
    }

    @Test("chain wire names map to display names; unknown ones pass through")
    func summaryChainDisplayName() {
        // Every wire name `getblockchaininfo` reports resolves to the name the
        // settings picker shows — "main" is never put in front of a person.
        for (wire, display) in [
            ("main", "Mainnet"), ("test", "Testnet"),
            ("signet", "Signet"), ("regtest", "Regtest"),
        ] {
            let text = String(
                localized: NodeAutomation.summary(
                    outcome: .started, syncEnding: .notMeasured,
                    chain: wire, height: 10, blocksBehind: nil,
                    blocksSinceLastCheck: nil, declinedReason: nil))
            #expect(text.contains("on \(display)"))
        }
        // A name the code does not recognise — a newer network, a fork — is
        // shown verbatim rather than dropped or mislabeled.
        let unknown = String(
            localized: NodeAutomation.summary(
                outcome: .started, syncEnding: .notMeasured,
                chain: "scalenet", height: 10, blocksBehind: nil,
                blocksSinceLastCheck: nil, declinedReason: nil))
        #expect(unknown.contains("scalenet"))
        // "testnet4" is the tempting mislabel: *a* testnet, but not the
        // "Testnet" the settings picker offers — verbatim is honest.
        let testnet4 = String(
            localized: NodeAutomation.summary(
                outcome: .started, syncEnding: .notMeasured,
                chain: "testnet4", height: 10, blocksBehind: nil,
                blocksSinceLastCheck: nil, declinedReason: nil))
        #expect(testnet4.contains("testnet4"))
        #expect(testnet4.contains("Testnet ") == false)
    }

    @Test("being caught up omits the behind-count instead of saying zero behind")
    func summaryCaughtUp() {
        let text = String(
            localized: NodeAutomation.summary(
                outcome: .started, syncEnding: .notMeasured,
                chain: "main", height: 900_000, blocksBehind: 0,
                blocksSinceLastCheck: nil, declinedReason: nil))
        #expect(text.contains("behind") == false)
    }

    @Test("no new blocks is stated, and is not the same as not knowing")
    func summaryZeroVersusUnknownGain() {
        let measuredZero = String(
            localized: NodeAutomation.summary(
                outcome: .started, syncEnding: .notMeasured,
                chain: "main", height: 10, blocksBehind: nil,
                blocksSinceLastCheck: 0, declinedReason: nil))
        let notMeasured = String(
            localized: NodeAutomation.summary(
                outcome: .started, syncEnding: .notMeasured,
                chain: "main", height: 10, blocksBehind: nil,
                blocksSinceLastCheck: nil, declinedReason: nil))
        // Zero rides the same catalog key as the counts — its `zero` plural
        // variant is what renders "No new blocks…".
        #expect(measuredZero.contains("No new blocks"))
        #expect(notMeasured.contains("No new blocks") == false)
        #expect(measuredZero != notMeasured)
    }

    @Test("one new block reads as singular")
    func summarySingularBlock() {
        let text = String(
            localized: NodeAutomation.summary(
                outcome: .started, syncEnding: .notMeasured,
                chain: "main", height: 10, blocksBehind: nil,
                blocksSinceLastCheck: 1, declinedReason: nil))
        #expect(text.contains("\(1.formatted()) new block since"))
    }

    @Test("an already-running node is reported as found, not started")
    func summaryAlreadyRunning() {
        let text = String(
            localized: NodeAutomation.summary(
                outcome: .alreadyRunning, syncEnding: .notMeasured,
                chain: "main", height: 7, blocksBehind: nil,
                blocksSinceLastCheck: nil, declinedReason: nil))
        #expect(text.contains("already running"))
    }

    // MARK: - The watch's ending sentences

    @Test("a watched catch-up appends its verdict after the outcome sentence")
    func summaryWatchedCaughtUp() {
        let text = String(
            localized: NodeAutomation.summary(
                outcome: .started, syncEnding: .caughtUp,
                chain: "signet", height: 915_000, blocksBehind: 0,
                blocksSinceLastCheck: nil, declinedReason: nil))
        #expect(text.contains("Node running on Signet"))
        #expect(text.contains("Caught up with the tip"))
    }

    @Test("an entry-gate decline says 'already at the tip', not 'caught up'")
    func summaryGateDeclinedCaughtUp() {
        // The node was at the tip when the run arrived — the watch never
        // began, so nothing was caught up *by* the run. `watched` picks the
        // wording; the outcome sentence stays truthful either way.
        let text = String(
            localized: NodeAutomation.summary(
                outcome: .alreadyRunning, syncEnding: .alreadyAtTip,
                chain: "main", height: 900_000, blocksBehind: 0,
                blocksSinceLastCheck: nil, declinedReason: nil))
        #expect(text.contains("Already at the tip"))
        #expect(text.contains("Caught up") == false)
    }

    @Test("a spent budget ends still syncing without naming the budget")
    func summaryStillSyncing() {
        // The budget figure stays out — "the run's time ran out" is honest
        // without inviting a question the sentence cannot answer.
        let text = String(
            localized: NodeAutomation.summary(
                outcome: .started, syncEnding: .stillSyncing,
                chain: "signet", height: 910_000, blocksBehind: 5_000,
                blocksSinceLastCheck: nil, declinedReason: nil))
        #expect(text.contains("Still syncing"))
        #expect(text.contains("\(5_000.formatted()) behind"))
    }

    @Test("a stalled watch names how long nothing advanced")
    func summaryNoProgressNamesTheSilence() {
        // `silentFor` is the stall the state measured — rendered as a
        // duration, not a fixed phrase, through the summary's shared style.
        let silence = Duration.seconds(240)
            .formatted(NodeAutomation.summarySilenceFormat)
        let text = String(
            localized: NodeAutomation.summary(
                outcome: .started, syncEnding: .noProgress(silentFor: .seconds(240)),
                chain: "signet", height: 910_000, blocksBehind: 5_000,
                blocksSinceLastCheck: nil, declinedReason: nil))
        #expect(text.contains("no progress for \(silence)"))
        #expect(text.contains("watch ended"))
    }

    @Test("a no-progress ending without a measured silence still names the ending")
    func summaryNoProgressWithoutDuration() {
        // `silentFor` is optional — the honest generic ending stands rather
        // than a fabricated figure.
        let text = String(
            localized: NodeAutomation.summary(
                outcome: .started, syncEnding: .noProgress(silentFor: nil),
                chain: "signet", height: 910_000, blocksBehind: 5_000,
                blocksSinceLastCheck: nil, declinedReason: nil))
        #expect(text.contains("no progress"))
        #expect(text.contains("watch ended"))
    }

    @Test("a stopped node does not claim to be running — the lead-in is rewritten")
    func summaryNodeStoppedTellsTheTruth() {
        // "Node running" would be a lie once the app has stopped it: the
        // verdict needs its own lead-in, and the last measured position is
        // what survives.
        let text = String(
            localized: NodeAutomation.summary(
                outcome: .started, syncEnding: .nodeStopped,
                chain: "signet", height: 910_000, blocksBehind: 5_000,
                blocksSinceLastCheck: nil, declinedReason: nil))
        #expect(text.contains("running on") == false)
        #expect(text.contains("stopped from the app"))
        #expect(text.contains("last measured on Signet at block \(910_000.formatted())"))
        #expect(text.contains("\(5_000.formatted()) behind"))
    }

    @Test("a mid-watch drift names the condition that ended the watch")
    func summaryDriftedConditionNamesIt() {
        // `notEnoughDisk`'s figure is interpolated typed — assert the
        // platform-formatted figure itself made it into the sentence.
        let diskFigure = Int64(3_000_000_000).formatted(.byteCount(style: .file))
        for (refusal, name) in [
            (NodePreflight.Refusal.filesNotReadable, "files stopped being readable"),
            (.chainFolderMissing, "nowhere left to write the chain data"),
            (.notEnoughDisk(freeBytes: 3_000_000_000), "Only \(diskFigure) of free space was left"),
            (.meteredNetwork, "network turned metered"),
            (.dataRestrictedNetwork, "Low Data Mode came on"),
            (.overheating, "device got too warm"),
            (.lowPowerMode, "Low Power Mode switched on"),
        ] as [(NodePreflight.Refusal, String)] {
            let text = String(
                localized: NodeAutomation.summary(
                    outcome: .started, syncEnding: .conditionsChanged(refusal),
                    chain: "main", height: 900_000, blocksBehind: 100,
                    blocksSinceLastCheck: nil, declinedReason: nil))
            #expect(text.contains(name), "\(refusal) should name \(name)")
            // The watch was running, so the frame is "ended", never
            // "did not start" — `Refusal.message`'s tail would be a lie here.
            #expect(text.contains("the watch ended"), "\(refusal)")
            #expect(text.contains("did not start") == false, "\(refusal)")
        }
    }

    @Test("an entry weigh-in refusal names the condition that kept the watch from starting")
    func summaryWeighInConditionNamesIt() {
        // The weigh-in happens before the watch commits: the frame is
        // "did not start", and the condition reads present-tense because it
        // stands now.
        let diskFigure = Int64(3_000_000_000).formatted(.byteCount(style: .file))
        for (refusal, name) in [
            (NodePreflight.Refusal.filesNotReadable, "files cannot be read"),
            (.chainFolderMissing, "nowhere to write the chain data"),
            (.notEnoughDisk(freeBytes: 3_000_000_000), "Only \(diskFigure) of free space is left"),
            (.meteredNetwork, "network is metered"),
            (.dataRestrictedNetwork, "Low Data Mode is on"),
            (.overheating, "device is too warm"),
            (.lowPowerMode, "Low Power Mode is on"),
        ] as [(NodePreflight.Refusal, String)] {
            let text = String(
                localized: NodeAutomation.summary(
                    outcome: .alreadyRunning, syncEnding: .watchRefused(refusal),
                    chain: "main", height: 900_000, blocksBehind: 100,
                    blocksSinceLastCheck: nil, declinedReason: nil))
            #expect(text.contains(name), "\(refusal) should name \(name)")
            #expect(text.contains("the watch did not start"), "\(refusal)")
            // The node is still running — the outcome lead-in stays true.
            #expect(text.contains("already running"), "\(refusal)")
        }
    }

    @Test("a weigh-in refusal without a named condition does not claim the watch ended")
    func summaryUnnamedWeighInRefusal() {
        // Same frame rule as the named refusals: the watch never began, so
        // "ended" would be a lie.
        let text = String(
            localized: NodeAutomation.summary(
                outcome: .started, syncEnding: .watchRefused(nil),
                chain: "signet", height: 190_000, blocksBehind: 10,
                blocksSinceLastCheck: nil,
                declinedReason: nil))
        #expect(text.hasSuffix("Conditions did not allow the watch to start."))
    }

    @Test("a drifted run without a named condition still ends honestly")
    func summaryConditionsChangedUnnamed() {
        let text = String(
            localized: NodeAutomation.summary(
                outcome: .started, syncEnding: .conditionsChanged(nil),
                chain: "main", height: 900_000, blocksBehind: 100,
                blocksSinceLastCheck: nil, declinedReason: nil))
        #expect(text.contains("Conditions changed"))
        #expect(text.contains("watch ended"))
    }

    @Test("the verdict comes last — history before what the run concluded")
    func summaryVerdictComesLast() {
        let text = String(
            localized: NodeAutomation.summary(
                outcome: .started, syncEnding: .caughtUp,
                chain: "signet", height: 915_000, blocksBehind: 0,
                blocksSinceLastCheck: 3, declinedReason: nil))
        // Status → what arrived since → the ending, in that order.
        let running = text.range(of: "Node running")
        let gained = text.range(of: "3 new blocks")
        let verdict = text.range(of: "Caught up")
        #expect(running != nil && gained != nil && verdict != nil)
        if let running, let gained, let verdict {
            #expect(running.lowerBound < gained.lowerBound)
            #expect(gained.lowerBound < verdict.lowerBound)
        }
    }

    @Test("notMeasured adds no verdict — the unmeasured sentence is unchanged")
    func summaryNotMeasuredAddsNothing() {
        // SC-005: the short action's output must be byte-identical to what it
        // was before the sync axis existed — exact equality, not fragments.
        // The figures go through the locale's grouping like any `%lld`, so
        // the expected text is built the same way rather than pinned to
        // en_US digits.
        let text = String(
            localized: NodeAutomation.summary(
                outcome: .started, syncEnding: .notMeasured,
                chain: "main", height: 900_000, blocksBehind: 12,
                blocksSinceLastCheck: 3, declinedReason: nil))
        #expect(
            text
                == "Node running on Mainnet at block \(900_000.formatted()), \(12.formatted()) behind. \(3.formatted()) new blocks since the last check.")
    }

    // MARK: - answerIsStillWanted(...)

    @Test("an answer that arrives during an ordinary wait is reported")
    func answerWantedNormally() {
        #expect(
            NodeAutomation.answerIsStillWanted(runWasCancelled: false, nodeIsStopped: false))
    }

    @Test("an answer that lands after the run was stopped is discarded")
    func answerDiscardedAfterCancellation() {
        // A question already in flight cannot be called back, so its answer can arrive
        // after the person tapped stop. Reporting it would announce a success for a run
        // they had just ended.
        #expect(
            NodeAutomation.answerIsStillWanted(runWasCancelled: true, nodeIsStopped: false)
                == false)
    }

    @Test("an answer that lands after the node was shut down is discarded")
    func answerDiscardedAfterNodeStopped() {
        // Someone can open the app mid-wait and stop the node. The answer still comes
        // back; reporting it would claim a running node that is not running.
        #expect(
            NodeAutomation.answerIsStillWanted(runWasCancelled: false, nodeIsStopped: true)
                == false)
    }

    @Test("both at once is still a discard, not a double negative")
    func answerDiscardedWhenBoth() {
        #expect(
            NodeAutomation.answerIsStillWanted(runWasCancelled: true, nodeIsStopped: true)
                == false)
    }

    // MARK: - ending(...)

    @Test("only a run that read a node fills the progress bar")
    func endingFillsBarOnlyOnSuccess() {
        // Regression: the bar used to be filled for every ending, so a run refused
        // because the network was metered still showed a completed bar.
        #expect(
            NodeAutomation.ending(
                outcome: .started, syncEnding: .notMeasured,
                summary: "x").fillsProgressBar)
        #expect(
            NodeAutomation.ending(
                outcome: .alreadyRunning, syncEnding: .notMeasured,
                summary: "x").fillsProgressBar)
        #expect(
            NodeAutomation.ending(
                outcome: .declined, syncEnding: .notMeasured,
                summary: "x").fillsProgressBar == false)
        #expect(
            NodeAutomation.ending(
                outcome: .didNotComeUp, syncEnding: .notMeasured,
                summary: "x").fillsProgressBar == false)
        #expect(
            NodeAutomation.ending(
                outcome: .noAnswer, syncEnding: .notMeasured,
                summary: "x").fillsProgressBar == false)
    }

    @Test("the card's detail line is the run's own summary sentence")
    func endingCarriesTheSummary() {
        // The summary is the one piece of text in the feature written to be read by a
        // person; the card must not paraphrase it into something that could disagree.
        let sentence = "Low Power Mode is on, so the node did not start."
        #expect(
            NodeAutomation.ending(
                outcome: .declined, syncEnding: .notMeasured,
                summary: sentence).detail == sentence)
    }

    @Test("every ending has a headline, and they tell the five apart")
    func endingTitles() {
        let titles = [
            NodeAutomation.ending(
                outcome: .started, syncEnding: .notMeasured,
                summary: "x").title,
            NodeAutomation.ending(
                outcome: .alreadyRunning, syncEnding: .notMeasured,
                summary: "x").title,
            NodeAutomation.ending(
                outcome: .declined, syncEnding: .notMeasured,
                summary: "x").title,
            NodeAutomation.ending(
                outcome: .didNotComeUp, syncEnding: .notMeasured,
                summary: "x").title,
            NodeAutomation.ending(
                outcome: .noAnswer, syncEnding: .notMeasured,
                summary: "x").title,
        ]
        #expect(titles.allSatisfy { $0.isEmpty == false })
        #expect(Set(titles).count == titles.count)
    }

    @Test("a run that was refused does not describe itself as running")
    func endingDeclinedDoesNotClaimRunning() {
        let declined = NodeAutomation.ending(
            outcome: .declined, syncEnding: .notMeasured,
            summary: "x").title
        let didNotComeUp = NodeAutomation.ending(
            outcome: .didNotComeUp, syncEnding: .notMeasured,
            summary: "x").title
        let noAnswer = NodeAutomation.ending(
            outcome: .noAnswer, syncEnding: .notMeasured,
            summary: "x").title
        #expect(declined.contains("running") == false)
        #expect(didNotComeUp.contains("running") == false)
        #expect(noAnswer.contains("running") == false)
    }

    @Test("a watched run's card names the sync ending, not the node outcome")
    func endingTitlesNameTheSyncEnding() {
        // With a real sync answer the card's job is to say how *syncing*
        // ended — the whole sentence keeps the outcome detail.
        #expect(
            NodeAutomation.ending(
                outcome: .started, syncEnding: .caughtUp,
                summary: "x").title == "Caught up")
        #expect(
            NodeAutomation.ending(
                outcome: .started, syncEnding: .stillSyncing,
                summary: "x").title == "Still syncing")
        #expect(
            NodeAutomation.ending(
                outcome: .started, syncEnding: .noProgress(silentFor: nil),
                summary: "x").title == "No progress")
        #expect(
            NodeAutomation.ending(
                outcome: .started, syncEnding: .nodeStopped,
                summary: "x").title == "Node stopped")
        #expect(
            NodeAutomation.ending(
                outcome: .started, syncEnding: .conditionsChanged(nil),
                summary: "x").title == "Conditions changed")
    }

    @Test("a weigh-in refusal card does not claim conditions changed")
    func endingGateConditionsTitle() {
        // The condition stood when the watch weighed in — nothing changed,
        // and the card must not say otherwise. The run itself measured and
        // kept a running node — the watch is what never began, so the
        // outcome stays `.alreadyRunning`; pairing the ending with
        // `.declined` would fail coherence.
        #expect(
            NodeAutomation.ending(
                outcome: .alreadyRunning, syncEnding: .watchRefused(nil),
                summary: "x").title == "Watch not started")
    }

    @Test("a gate-declined catch-up card says 'Synced to tip', not 'Caught up'")
    func endingGateCaughtUpTitle() {
        // Nothing was caught up *by* the run — the entry gate found the node
        // already there.
        #expect(
            NodeAutomation.ending(
                outcome: .alreadyRunning, syncEnding: .alreadyAtTip,
                summary: "x").title == "Synced to tip")
    }

    @Test("only a caught-up ending fills the bar on a watched run")
    func endingFillsBarOnlyOnCaughtUp() {
        // "Keep it syncing" is finished only when the node reached the tip —
        // every other watch ending leaves work undone, so the bar must not
        // claim the run completed it.
        for ending: NodeAutomation.SyncEnding in [
            .stillSyncing, .noProgress(silentFor: nil), .nodeStopped,
            .conditionsChanged(nil),
        ] {
            #expect(
                NodeAutomation.ending(
                    outcome: .started, syncEnding: ending,
                    summary: "x").fillsProgressBar == false,
                "\(ending) must not fill")
        }
        #expect(
            NodeAutomation.ending(
                outcome: .started, syncEnding: .caughtUp,
                summary: "x").fillsProgressBar)
        // A gate-declined catch-up is just as complete — the node was at the
        // tip when the run arrived.
        #expect(
            NodeAutomation.ending(
                outcome: .alreadyRunning, syncEnding: .alreadyAtTip,
                summary: "x").fillsProgressBar)
    }

    @Test("every ending collapses to the right public result and watch claim")
    func syncEndingMappings() {
        // `result` is the public collapse; `watched` is derived, never
        // passed — a gate ending and its mid-watch twin share the public
        // case but not the claim.
        let cases: [(NodeAutomation.SyncEnding, NodeAutomation.SyncResult, Bool)] = [
            (.caughtUp, .caughtUp, true),
            (.alreadyAtTip, .caughtUp, false),
            (.stillSyncing, .stillSyncing, true),
            (.noProgress(silentFor: nil), .noProgress, true),
            (.noProgress(silentFor: .seconds(60)), .noProgress, true),
            (.nodeStopped, .nodeStopped, true),
            (.conditionsChanged(nil), .conditionsChanged, true),
            (.watchRefused(nil), .conditionsChanged, false),
            (.notMeasured, .notMeasured, false),
        ]
        for (ending, result, watched) in cases {
            #expect(ending.result == result, "\(ending)")
            #expect(ending.watched == watched, "\(ending)")
        }
    }

    @Test("an outcome and a sync ending must agree about whether anything was measured")
    func outcomeEndingCoherence() {
        // The rule the report enforces: real endings ride only on a measured
        // run; a declined, unstarted, or unanswered run claims nothing — a
        // stall ends on the measured report it already had, never a blanked
        // `noAnswer`.
        let realEndings: [NodeAutomation.SyncEnding] = [
            .caughtUp, .alreadyAtTip, .stillSyncing,
            .noProgress(silentFor: nil), .noProgress(silentFor: .seconds(240)),
            .nodeStopped, .conditionsChanged(nil), .conditionsChanged(.meteredNetwork),
            .watchRefused(nil), .watchRefused(.lowPowerMode),
        ]
        for outcome in [NodeAutomation.Outcome.declined, .didNotComeUp, .noAnswer] {
            for ending in realEndings {
                #expect(
                    !NodeAutomation.isCoherent(outcome: outcome, ending: ending),
                    "\(outcome) cannot carry \(ending)")
            }
            #expect(
                NodeAutomation.isCoherent(outcome: outcome, ending: .notMeasured),
                "\(outcome) carries only notMeasured")
        }
        for outcome in [NodeAutomation.Outcome.started, .alreadyRunning] {
            for ending in realEndings + [.notMeasured] {
                #expect(
                    NodeAutomation.isCoherent(outcome: outcome, ending: ending),
                    "\(outcome) may carry \(ending)")
            }
        }
    }

    @Test("the in-progress headline is set")
    func inProgressTitleExists() {
        #expect(NodeAutomation.inProgressTitle.isEmpty == false)
    }

    @Test("the watching headline is the plan's pinned wording, distinct from the checking one")
    func watchingTitleIsPinned() {
        // FR-003 / plan §3.4: once a watch commits, "checking" becomes
        // "syncing" — the honest verb for the one thing the run is doing.
        #expect(NodeAutomation.watchingTitle == "Syncing the Bitcoin node")
        #expect(NodeAutomation.watchingTitle != NodeAutomation.inProgressTitle)
    }

    // MARK: - The in-watch detail line

    @Test("the watch detail line reports absolute position with grouped digits")
    func watchDetailPosition() {
        // Apple's `localizedAdditionalDescription` convention is terse
        // status text — "Block 843,210 of 915,000" in en_US — and the
        // figures go through the locale's grouping, so the expectations
        // are built the same way rather than pinned to one locale.
        let text = String(
            localized: NodeAutomation.watchDetail(
                height: 843_210, headers: 915_000, silentFor: nil))
        #expect(text.contains(843_210.formatted()))
        #expect(text.contains(915_000.formatted()))
        #expect(text.contains("last gain") == false)
    }

    @Test("the detail line gains a staleness clause once the caller names the silence")
    func watchDetailStalenessClause() {
        // `silentFor` selects the second whole-line key and supplies the
        // duration — rendered abbreviated on the status line ("3 min").
        let silence = Duration.seconds(180)
            .formatted(NodeAutomation.detailSilenceFormat)
        let text = String(
            localized: NodeAutomation.watchDetail(
                height: 843_210, headers: 915_000, silentFor: .seconds(180)))
        #expect(text.contains("\(843_210.formatted()) of \(915_000.formatted())"))
        #expect(text.contains("last gain \(silence) ago"))
    }

    @Test("the staleness clause renders longer silences in hours and minutes")
    func watchDetailLongStaleness() {
        let text = String(
            localized: NodeAutomation.watchDetail(
                height: 100, headers: 200, silentFor: .seconds(4_800)))
        #expect(
            text.contains(
                Duration.seconds(4_800)
                    .formatted(NodeAutomation.detailSilenceFormat)))
    }

    // MARK: - Watch entry

    /// The wall-clock instant every gate test measures tip age against — fixed,
    /// so a "stale" or "fresh" tip is a plain offset from it.
    private let watchNow = Date(timeIntervalSince1970: 1_713_500_000)

    @Test("the IBD flag enters the watch even with no gap and a fresh tip")
    func gateEntersOnFlag() {
        // The flag is the never-synced / day-stale signal — it admits alone.
        #expect(
            NodeAutomation.watchEntry(
                reading: reading(
                    "main", 800_000, isInitialBlockDownload: true, tipTime: watchNow),
                now: watchNow)
                == .enter)
    }

    @Test("an open header gap enters the watch")
    func gateEntersOnGap() {
        // Flag clear, tip fresh — but the node knows headers it does not hold.
        #expect(
            NodeAutomation.watchEntry(
                reading: reading("main", 800_000, behind: 200, tipTime: watchNow),
                now: watchNow)
                == .enter)
    }

    @Test("a stale tip enters the watch — the warm-restart window the other signals miss")
    func gateEntersOnStaleTip() {
        // A restarted synced node: the flag already cleared at chain-tip load and
        // no gap has been fetched yet, while hours of blocks wait. The tip's own
        // age is the signal that still enters.
        #expect(
            NodeAutomation.watchEntry(
                reading: reading(
                    "main", 800_000, tipTime: watchNow.addingTimeInterval(-7_200)),
                now: watchNow)
                == .enter)
    }

    @Test("flag clear, gap closed, tip fresh declines as caught up")
    func gateDeclinesCaughtUp() {
        // The watch's proof evaluated once at entry: the node was already at the
        // tip when the run arrived — an answer, not a missing measurement
        // (FR-005).
        #expect(
            NodeAutomation.watchEntry(
                reading: reading("main", 800_000, tipTime: watchNow),
                now: watchNow)
                == .decline(.caughtUp))
    }

    @Test("regtest never enters — even with the flag set or a gap open, it reports notMeasured")
    func gateDeclinesRegtest() {
        // A self-defined chain is definitionally at its own tip (FR-015): a
        // just-started regtest can sit with the IBD flag set and a stale tip and
        // still must not enter — the decline is absolute, checked before any
        // signal.
        #expect(
            NodeAutomation.watchEntry(
                reading: reading(
                    "regtest", 0, isInitialBlockDownload: true,
                    tipTime: watchNow.addingTimeInterval(-7_200)),
                now: watchNow)
                == .decline(.notMeasured))
        #expect(
            NodeAutomation.watchEntry(
                reading: reading("regtest", 100, behind: 50, tipTime: watchNow),
                now: watchNow)
                == .decline(.notMeasured))
        // And a settled regtest — flag clear, gap closed, a just-mined tip —
        // still reports notMeasured, never caughtUp: "still syncing" is
        // ill-defined on the chain, so the decline names the missing
        // measurement, not a tip it does not have.
        #expect(
            NodeAutomation.watchEntry(
                reading: reading("regtest", 800_000, tipTime: watchNow),
                now: watchNow)
                == .decline(.notMeasured))
    }

    @Test("an unknown chain is weighed on the signals like a known one")
    func gateTreatsUnknownChainNormally() {
        // A name with no picker counterpart — a fork's, a future network's —
        // resolves to no known network, so it is judged on the three signals
        // like any real chain.
        #expect(
            NodeAutomation.watchEntry(
                reading: reading(
                    "scalenet", 100, isInitialBlockDownload: true, tipTime: watchNow),
                now: watchNow)
                == .enter)
        #expect(
            NodeAutomation.watchEntry(
                reading: reading("scalenet", 100, tipTime: watchNow),
                now: watchNow)
                == .decline(.caughtUp))
    }

    @Test("a tip exactly at the freshness boundary still reads fresh")
    func tipAtBoundaryIsFresh() {
        // "Older than" is the stale direction: at exactly the threshold the tip
        // is still inside it — the same bar the caught-up proof applies (T012).
        #expect(
            NodeAutomation.tipIsFresh(
                tipTime: watchNow.addingTimeInterval(-3_600), now: watchNow))
    }

    @Test("a tip past the freshness boundary reads stale")
    func tipPastBoundaryIsStale() {
        #expect(
            NodeAutomation.tipIsFresh(
                tipTime: watchNow.addingTimeInterval(-3_600.001), now: watchNow)
                == false)
    }

    @Test("a tip stamped in the future reads fresh — miner skew, not staleness")
    func futureTipIsFresh() {
        // `time` is miner-set and consensus-tolerant to ~2 h ahead; a negative
        // age can never mean "older than".
        #expect(
            NodeAutomation.tipIsFresh(
                tipTime: watchNow.addingTimeInterval(7_200), now: watchNow))
    }

    @Test("the freshness figure is the spec's sixty minutes, and an injected bound is honored")
    func freshnessThreshold() {
        #expect(NodeAutomation.tipFreshnessThreshold == .seconds(3_600))
        // The injected `within` is what lets the gate and the caught-up proof
        // (T012) share one boundary — tests shrink the window rather than
        // recompute ages around 3,600 seconds.
        #expect(
            NodeAutomation.tipIsFresh(
                tipTime: watchNow.addingTimeInterval(-61), now: watchNow,
                within: .seconds(60)) == false)
        #expect(
            NodeAutomation.tipIsFresh(
                tipTime: watchNow.addingTimeInterval(-59), now: watchNow,
                within: .seconds(60)))
    }

    // MARK: - The entry weigh-in

    /// The weigh-in's healthy baseline — every parameter a measured fact the
    /// gather supplies. The two file conditions have no parameter at all: a
    /// node answering RPCs has already proven it read the chain, so the
    /// weigh-in pins both satisfied rather than re-reading them (and never
    /// spends `prepareChainFolder()`'s write).
    private func weighIn(
        lowPowerModeEnabled: Bool = false,
        networkIsMetered: Bool = false,
        networkIsDataRestricted: Bool = false,
        thermalState: ProcessInfo.ThermalState = .nominal,
        freeDiskBytes: Int64? = NodePreflight.minimumFreeDiskBytes * 8
    ) -> NodePreflight.Refusal? {
        NodeAutomation.entryWeighIn(
            lowPowerModeEnabled: lowPowerModeEnabled,
            networkIsMetered: networkIsMetered,
            networkIsDataRestricted: networkIsDataRestricted,
            thermalState: thermalState,
            freeDiskBytes: freeDiskBytes)
    }

    @Test("a healthy device lets the run commit to the watch")
    func weighInHealthyProceeds() {
        #expect(weighIn() == nil)
    }

    @Test("a metered network refuses the watch, exactly as it refuses a start")
    func weighInMetered() {
        #expect(weighIn(networkIsMetered: true) == .meteredNetwork)
    }

    @Test("a data-restricted network refuses the watch even when it is not metered")
    func weighInDataRestricted() {
        #expect(weighIn(networkIsDataRestricted: true) == .dataRestrictedNetwork)
    }

    @Test("battery saver refuses the weigh-in — the start bar applies at watch entry")
    func weighInLowPowerMode() {
        // FR-011's "accepted" is the drift check's delta rule — a watch that
        // committed is not punished for having had it on — not an admission.
        // A watch is minutes of sustained work the mode was switched on to
        // avoid, and ending the run is the one step that relieves it (the app
        // suspends, freezing the in-process daemon).
        #expect(weighIn(lowPowerModeEnabled: true) == .lowPowerMode)
    }

    @Test("the weigh-in refuses at serious heat — the entry bar, not the drift check's critical-only")
    func weighInThermalEntryBar() {
        for state: ProcessInfo.ThermalState in [.serious, .critical] {
            #expect(weighIn(thermalState: state) == .overheating)
        }
        for state: ProcessInfo.ThermalState in [.nominal, .fair] {
            #expect(weighIn(thermalState: state) == nil)
        }
    }

    @Test("too little free space refuses the watch and reports how much is left")
    func weighInNotEnoughDisk() {
        let free = NodePreflight.minimumFreeDiskBytes / 2
        #expect(weighIn(freeDiskBytes: free) == .notEnoughDisk(freeBytes: free))
    }

    @Test("free space at the floor commits, and unknown space never refuses")
    func weighInDiskBoundary() {
        #expect(weighIn(freeDiskBytes: NodePreflight.minimumFreeDiskBytes) == nil)
        #expect(
            weighIn(freeDiskBytes: NodePreflight.minimumFreeDiskBytes - 1)
                == .notEnoughDisk(freeBytes: NodePreflight.minimumFreeDiskBytes - 1))
        // The answering node proves the chain folder exists, but the disk read
        // itself can still fail — unknown is never treated as too little.
        #expect(weighIn(freeDiskBytes: nil) == nil)
    }

    @Test("the weigh-in keeps the preflight order — the most fundamental reason wins, battery saver last")
    func weighInSharedPriority() {
        // The order is `refusal(for:)`'s own — the weigh-in delegates rather
        // than restating it, so the most-fundamental-first contract cannot
        // drift between the two call sites.
        #expect(
            weighIn(networkIsMetered: true, freeDiskBytes: 0)
                == .notEnoughDisk(freeBytes: 0))
        #expect(
            weighIn(lowPowerModeEnabled: true, thermalState: .serious)
                == .overheating)
        #expect(
            weighIn(lowPowerModeEnabled: true, networkIsMetered: true)
                == .meteredNetwork)
    }

    @Test("an answering node settles the file checks — the weigh-in is the start bar, verbatim")
    func weighInFileConditionsUnreachable() {
        // An exhaustive sweep: `filesReadable`/`chainFolderExists` are pinned
        // satisfied inside the function, so across every input the weigh-in is
        // exactly `refusal(for:)` on those synthesized conditions — the same
        // bar a start faces, which is FR-012's whole point.
        for thermal: ProcessInfo.ThermalState in [.nominal, .fair, .serious, .critical] {
            for lowPower in [false, true] {
                for metered in [false, true] {
                    for restricted in [false, true] {
                        for disk in [nil, 0, NodePreflight.minimumFreeDiskBytes] {
                            #expect(
                                weighIn(
                                    lowPowerModeEnabled: lowPower,
                                    networkIsMetered: metered,
                                    networkIsDataRestricted: restricted,
                                    thermalState: thermal,
                                    freeDiskBytes: disk)
                                    == NodePreflight.refusal(for: .init(
                                        filesReadable: true, chainFolderExists: true,
                                        lowPowerModeEnabled: lowPower,
                                        networkIsMetered: metered,
                                        networkIsDataRestricted: restricted,
                                        thermalState: thermal,
                                        freeDiskBytes: disk)))
                        }
                    }
                }
            }
        }
    }

    @Test("the disk floor is injectable, like the preflight's")
    func weighInDiskFloorInjection() {
        let free = NodePreflight.minimumFreeDiskBytes * 2
        #expect(
            NodeAutomation.entryWeighIn(
                lowPowerModeEnabled: false, networkIsMetered: false,
                networkIsDataRestricted: false, thermalState: .nominal,
                freeDiskBytes: free,
                minimumFreeDiskBytes: free * 2)
                == .notEnoughDisk(freeBytes: free))
    }

    // MARK: - SyncWatchState

    /// A state entered on the given reading at `t0`; tests advance the clock by
    /// hand from there. The leashes default to the real figures — an injected
    /// pair is only for proving the injection seam works.
    private func watchState(
        at instant: ContinuousClock.Instant,
        entry: NodeAutomation.LiveReading,
        lowPowerMode: Bool = false,
        unproductiveLeash: Duration = NodeAutomation.unproductiveLeash,
        flatWindowLeash: Duration = NodeAutomation.flatWindowLeash
    ) -> NodeAutomation.SyncWatchState<ContinuousClock.Instant> {
        NodeAutomation.SyncWatchState(
            at: instant, entry: entry, lowPowerMode: lowPowerMode,
            unproductiveLeash: unproductiveLeash, flatWindowLeash: flatWindowLeash)
    }

    @Test("watch entry seeds the baseline and best-seen heights and owes no leash time")
    func watchEntrySeeds() {
        let t0 = ContinuousClock.now
        let state = watchState(
            at: t0, entry: reading("main", 800_000, behind: 200), lowPowerMode: true)
        #expect(state.baseline == baseline("main", 800_000))
        #expect(state.baselineHeaders == 800_200)
        #expect(state.bestBlocks == 800_000)
        #expect(state.bestHeaders == 800_200)
        // A gap at entry does not latch the headers flag — the latch wants
        // growth *past the entry figure*, not headers standing over blocks.
        #expect(state.headersAdvanced == false)
        #expect(state.unproductive == .zero)
        #expect(state.flatWindow == .zero)
        #expect(state.stall == nil)
        #expect(state.lowPowerModeAtEntry)
    }

    @Test("a pass with no fresh reading feeds the unproductive leash alone")
    func absentReadingFeedsUnproductive() {
        let t0 = ContinuousClock.now
        var state = watchState(at: t0, entry: reading("main", 800_000))
        #expect(
            state.advance(instant: t0.advanced(by: .seconds(60)), reading: nil)
                == .unproductive)
        #expect(state.unproductive == .seconds(60))
        #expect(state.flatWindow == .zero)
        #expect(state.stall == nil)
    }

    @Test("a flat reading with undone work showing feeds the unproductive leash")
    func flatWithGapFeedsUnproductive() {
        let t0 = ContinuousClock.now
        var state = watchState(at: t0, entry: reading("main", 800_000, behind: 200))
        // Same heights again — nothing advanced, but `headers > blocks` means
        // the node has shown work it is not doing.
        #expect(
            state.advance(
                instant: t0.advanced(by: .seconds(60)),
                reading: reading("main", 800_000, behind: 200))
                == .unproductive)
        #expect(state.unproductive == .seconds(60))
        #expect(state.flatWindow == .zero)
    }

    @Test("a flat reading with nothing provably undone feeds the flat-window leash")
    func flatNoGapFeedsFlatWindow() {
        let t0 = ContinuousClock.now
        var state = watchState(at: t0, entry: reading("main", 800_000))
        #expect(
            state.advance(
                instant: t0.advanced(by: .seconds(60)),
                reading: reading("main", 800_000))
                == .flatWindow)
        #expect(state.flatWindow == .seconds(60))
        #expect(state.unproductive == .zero)
    }

    @Test("a reading that gains blocks resets both leashes and feeds none")
    func advancingBlocksResets() {
        let t0 = ContinuousClock.now
        var state = watchState(at: t0, entry: reading("main", 800_000))
        _ = state.advance(instant: t0.advanced(by: .seconds(60)), reading: nil)
        _ = state.advance(
            instant: t0.advanced(by: .seconds(90)), reading: reading("main", 800_000))
        #expect(state.unproductive == .seconds(60))
        #expect(state.flatWindow == .seconds(30))
        #expect(
            state.advance(
                instant: t0.advanced(by: .seconds(95)),
                reading: reading("main", 800_010))
                == nil)
        #expect(state.unproductive == .zero)
        #expect(state.flatWindow == .zero)
        #expect(state.bestBlocks == 800_010)
    }

    @Test("a reading that gains only headers counts as a gain")
    func advancingHeadersResets() {
        let t0 = ContinuousClock.now
        var state = watchState(at: t0, entry: reading("main", 800_000))
        _ = state.advance(instant: t0.advanced(by: .seconds(60)), reading: nil)
        // Header fetch legitimately freezes blocks while the gap opens — a
        // headers gain is still a gain, and it latches the proof's leg.
        #expect(
            state.advance(
                instant: t0.advanced(by: .seconds(65)),
                reading: reading("main", 800_000, behind: 50))
                == nil)
        #expect(state.unproductive == .zero)
        #expect(state.headersAdvanced)
    }

    @Test("the headers-advanced latch sets only above the entry figure")
    func headersLatchAboveEntry() {
        let t0 = ContinuousClock.now
        var state = watchState(at: t0, entry: reading("main", 800_000, behind: 200))
        _ = state.advance(
            instant: t0.advanced(by: .seconds(5)),
            reading: reading("main", 800_000, behind: 200))
        #expect(state.headersAdvanced == false)
        _ = state.advance(
            instant: t0.advanced(by: .seconds(10)),
            reading: reading("main", 800_000, behind: 201))
        #expect(state.headersAdvanced)
    }

    @Test("a blocks gain never sets the headers latch")
    func blocksGainDoesNotLatch() {
        let t0 = ContinuousClock.now
        var state = watchState(at: t0, entry: reading("main", 800_000, behind: 200))
        _ = state.advance(
            instant: t0.advanced(by: .seconds(5)),
            reading: reading("main", 800_100, behind: 100))
        #expect(state.bestBlocks == 800_100)
        #expect(state.headersAdvanced == false)
    }

    @Test("feeding one leash never resets the other")
    func leashesAccumulateIndependently() {
        let t0 = ContinuousClock.now
        var state = watchState(at: t0, entry: reading("main", 800_000))
        _ = state.advance(instant: t0.advanced(by: .seconds(60)), reading: nil)
        _ = state.advance(
            instant: t0.advanced(by: .seconds(90)), reading: reading("main", 800_000))
        _ = state.advance(instant: t0.advanced(by: .seconds(120)), reading: nil)
        // Silence between flat answers still counts toward `unproductive`, and
        // the flat stretch kept its own count across the timed-out question.
        #expect(state.unproductive == .seconds(90))
        #expect(state.flatWindow == .seconds(30))
        #expect(state.stall == nil)
    }

    @Test("the unproductive leash trips the moment silence reaches its bound")
    func unproductiveTripsAtBound() {
        let t0 = ContinuousClock.now
        var state = watchState(at: t0, entry: reading("main", 800_000))
        _ = state.advance(instant: t0.advanced(by: .seconds(119)), reading: nil)
        #expect(state.stall == nil)
        _ = state.advance(instant: t0.advanced(by: .seconds(120)), reading: nil)
        #expect(state.stall == .unproductive)
    }

    @Test("the flat-window leash trips at its own longer bound")
    func flatWindowTripsAtBound() {
        let t0 = ContinuousClock.now
        var state = watchState(at: t0, entry: reading("main", 800_000))
        _ = state.advance(
            instant: t0.advanced(by: .seconds(239)), reading: reading("main", 800_000))
        #expect(state.stall == nil)
        _ = state.advance(
            instant: t0.advanced(by: .seconds(240)), reading: reading("main", 800_000))
        #expect(state.stall == .flatWindow)
    }

    @Test("a suspended run's giant delta trips the leash in one pass")
    func giantDeltaTripsAtOnce() {
        let t0 = ContinuousClock.now
        var state = watchState(at: t0, entry: reading("main", 800_000))
        // A frozen process wakes with the whole gap as one delta — the correct
        // accounting, since the in-process daemon froze for exactly as long.
        _ = state.advance(instant: t0.advanced(by: .seconds(300)), reading: nil)
        #expect(state.stall == .unproductive)
    }

    @Test("a rewound reading is flat — never a gain, never a new low to measure from")
    func rewoundReadingIsFlat() {
        let t0 = ContinuousClock.now
        var state = watchState(at: t0, entry: reading("main", 800_120))
        // Reorged below the best seen, gap closed: flat, on the long leash.
        #expect(
            state.advance(
                instant: t0.advanced(by: .seconds(30)),
                reading: reading("main", 800_090))
                == .flatWindow)
        // Reorged with a reopened gap (`headers > blocks`): still flat, but the
        // work showing makes it unproductive — the spec's mid-watch-reorg edge.
        #expect(
            state.advance(
                instant: t0.advanced(by: .seconds(60)),
                reading: reading("main", 800_090, behind: 30))
                == .unproductive)
        #expect(state.bestBlocks == 800_120)
    }

    @Test("a backwards instant feeds nothing and never re-anchors the delta")
    func backwardsInstantIsInert() {
        let t0 = ContinuousClock.now
        var state = watchState(at: t0, entry: reading("main", 800_000))
        _ = state.advance(instant: t0.advanced(by: .seconds(-10)), reading: nil)
        #expect(state.unproductive == .zero)
        _ = state.advance(instant: t0.advanced(by: .seconds(20)), reading: nil)
        // 20 s of silence, not 30 — storing the earlier instant would have
        // handed the rewound span to this pass's delta.
        #expect(state.unproductive == .seconds(20))
    }

    @Test("the leash figures are the spec's — two minutes of silence, four flat")
    func leashDefaults() {
        #expect(NodeAutomation.unproductiveLeash == .seconds(120))
        #expect(NodeAutomation.flatWindowLeash == .seconds(240))
        // The init's defaults defer to the statics — a state built without
        // leash arguments must carry the spec figures, not literals that could
        // silently drift from them.
        let state = NodeAutomation.SyncWatchState(
            at: ContinuousClock.now, entry: reading("main", 800_000),
            lowPowerMode: false)
        #expect(state.unproductiveLeash == NodeAutomation.unproductiveLeash)
        #expect(state.flatWindowLeash == NodeAutomation.flatWindowLeash)
    }

    @Test("a gain after a tripped leash clears the verdict — stall follows the timers")
    func gainClearsStall() {
        let t0 = ContinuousClock.now
        var state = watchState(at: t0, entry: reading("main", 800_000))
        _ = state.advance(instant: t0.advanced(by: .seconds(120)), reading: nil)
        #expect(state.stall == .unproductive)
        // The run would already have ended on the trip — but if one more
        // reading lands, the state answers honestly: a gain resets, and
        // nothing is owed.
        _ = state.advance(
            instant: t0.advanced(by: .seconds(125)), reading: reading("main", 800_010))
        #expect(state.stall == nil)
    }

    @Test("an injected leash is honored")
    func injectedLeashHonored() {
        let t0 = ContinuousClock.now
        var state = watchState(
            at: t0, entry: reading("main", 800_000), unproductiveLeash: .seconds(10))
        _ = state.advance(instant: t0.advanced(by: .seconds(10)), reading: nil)
        #expect(state.stall == .unproductive)
    }

    @Test("with both leashes tripped the unproductive verdict stands")
    func stallPrefersUnproductive() {
        let t0 = ContinuousClock.now
        var state = watchState(at: t0, entry: reading("main", 800_000))
        _ = state.advance(instant: t0.advanced(by: .seconds(130)), reading: nil)
        _ = state.advance(
            instant: t0.advanced(by: .seconds(370)), reading: reading("main", 800_000))
        // Both stand over — the tighter signal reports first.
        #expect(state.unproductive >= NodeAutomation.unproductiveLeash)
        #expect(state.flatWindow >= NodeAutomation.flatWindowLeash)
        #expect(state.stall == .unproductive)
    }

    // MARK: - The catch-up proof

    /// A `PeerEvidence` row built the wire-decoding way — a `getpeerinfo`
    /// JSON row through `PeerInfo` — so the two fields the proof reads are
    /// the ones a real answer carries.
    private func peerEvidence(
        connectionType: String?, inbound: Bool, syncedHeaders: Int
    ) throws -> NodeAutomation.PeerEvidence {
        try NodeAutomation.PeerEvidence(
            Self.decodePeer(
                connectionType: connectionType, inbound: inbound,
                syncedHeaders: syncedHeaders))
    }

    /// The settled shape of "still syncing with nothing provably left": flag
    /// clear, gap closed, tip two hours stale — what a warm restart on a
    /// quiet chain reports every pass. Only watched growth, a fresh tip, or
    /// confirming peers can prove such a node caught up.
    private func settledReading(
        _ chain: String = "main", _ height: Int = 800_000
    ) -> NodeAutomation.LiveReading {
        reading(chain, height, tipTime: watchNow.addingTimeInterval(-7_200))
    }

    @Test("a set IBD flag is never caught up — no leg can certify past it")
    func flagVetoesEveryLeg() throws {
        // Gap closed, tip fresh, headers advanced, two peers confirming —
        // every leg present, still not caught up. The flag is Core's own
        // verdict; certifying past it would contradict the node (FR-006).
        let peers = try [
            peerEvidence(
                connectionType: "outbound-full-relay", inbound: false,
                syncedHeaders: 800_000),
            peerEvidence(
                connectionType: "block-relay-only", inbound: false,
                syncedHeaders: 800_000),
        ]
        #expect(
            NodeAutomation.caughtUp(
                reading: reading(
                    "main", 800_000, isInitialBlockDownload: true, tipTime: watchNow),
                headersAdvanced: true, peers: peers, now: watchNow)
                == false)
    }

    @Test("an open gap is never caught up, even when headers advanced this run")
    func openGapNeverCaughtUp() {
        // Header-fetch in flight: headers grew past the entry figure, but
        // blocks have not closed on them — the node is plainly still syncing.
        #expect(
            NodeAutomation.caughtUp(
                reading: reading("main", 800_000, behind: 200, tipTime: watchNow),
                headersAdvanced: true, peers: [], now: watchNow)
                == false)
    }

    @Test("watched header growth with a closed gap proves the catch-up")
    func headersAdvancedProves() {
        // The warm-restart catch-up the watch exists for: tip still stale
        // and no peer answer, but headers moved past the entry figure.
        #expect(
            NodeAutomation.caughtUp(
                reading: settledReading(),
                headersAdvanced: true, peers: [], now: watchNow))
    }

    @Test("a fresh tip proves the catch-up with no watched growth")
    func freshTipProves() {
        // Blocks closed on already-known headers — headers never advanced,
        // but the tip that just connected is recent. The same shape the
        // entry gate declines `caughtUp`, judged identically mid-watch.
        #expect(
            NodeAutomation.caughtUp(
                reading: reading("main", 800_000),
                headersAdvanced: false, peers: [], now: watchNow))
    }

    @Test("two confirming outbound block-serving peers prove the quiet-chain catch-up")
    func peerConfirmationProves() throws {
        // Nothing new exists for headers to advance to, the tip is stale —
        // and two block-serving peers' completed exchanges say they hold
        // nothing higher. That is the proof this leg exists for.
        let peers = try [
            peerEvidence(
                connectionType: "outbound-full-relay", inbound: false,
                syncedHeaders: 800_000),
            peerEvidence(
                connectionType: "block-relay-only", inbound: false,
                syncedHeaders: 800_000),
        ]
        #expect(
            NodeAutomation.caughtUp(
                reading: settledReading(),
                headersAdvanced: false, peers: peers, now: watchNow))
    }

    @Test("a single confirming peer is not a quorum")
    func onePeerIsNoQuorum() throws {
        let peers = try [
            peerEvidence(
                connectionType: "outbound-full-relay", inbound: false,
                syncedHeaders: 800_000),
        ]
        #expect(
            NodeAutomation.caughtUp(
                reading: settledReading(),
                headersAdvanced: false, peers: peers, now: watchNow)
                == false)
    }

    @Test("inbound, manual, and unclassified peers never count — attacker-selected evidence is no evidence")
    func onlyBlockServingKindsCount() throws {
        // One qualifying peer plus an inbound, a manual, and an
        // unclassifiable outbound peer all confirming the same height:
        // still only one that counts.
        let peers = try [
            peerEvidence(
                connectionType: "outbound-full-relay", inbound: false,
                syncedHeaders: 800_000),
            peerEvidence(connectionType: "inbound", inbound: true, syncedHeaders: 800_000),
            peerEvidence(connectionType: "manual", inbound: false, syncedHeaders: 800_000),
            peerEvidence(connectionType: nil, inbound: false, syncedHeaders: 800_000),
        ]
        #expect(
            NodeAutomation.caughtUp(
                reading: settledReading(),
                headersAdvanced: false, peers: peers, now: watchNow)
                == false)
    }

    @Test("peers reporting a different height are no evidence")
    func mismatchedPeerHeightIsNoEvidence() throws {
        // One peer announcing a newer best block, one that never announced
        // anything held — neither equals our headers figure.
        let peers = try [
            peerEvidence(
                connectionType: "outbound-full-relay", inbound: false,
                syncedHeaders: 800_001),
            peerEvidence(
                connectionType: "block-relay-only", inbound: false, syncedHeaders: -1),
        ]
        #expect(
            NodeAutomation.caughtUp(
                reading: settledReading(),
                headersAdvanced: false, peers: peers, now: watchNow)
                == false)
    }

    @Test("no peer answer is no evidence — an absent or timed-out ask proves nothing")
    func absentPeersAreNoEvidence() {
        #expect(
            NodeAutomation.caughtUp(
                reading: settledReading(),
                headersAdvanced: false, peers: [], now: watchNow)
                == false)
    }

    @Test("blocks taller than headers certifies nothing — a nonsense reading is not a closed gap")
    func headersBelowBlocksIsNoClosedGap() {
        // `headers < blocks` cannot come from a real node; if one ever did,
        // the proof treats it as unproven rather than reading "gap closed"
        // into a figure that means something is wrong.
        #expect(
            NodeAutomation.caughtUp(
                reading: reading("main", 800_000, behind: -50, tipTime: watchNow),
                headersAdvanced: false, peers: [], now: watchNow)
                == false)
    }

    @Test("the state's latch is the proof's growth leg — a watched fetch then a closed gap")
    func stateLatchFeedsProof() {
        let t0 = ContinuousClock.now
        var state = watchState(
            at: t0,
            entry: reading(
                "main", 800_000, behind: 200,
                tipTime: watchNow.addingTimeInterval(-7_200)))
        // Headers arrive — the pass is a gain and the latch sets.
        _ = state.advance(
            instant: t0.advanced(by: .seconds(5)),
            reading: reading(
                "main", 800_000, behind: 300,
                tipTime: watchNow.addingTimeInterval(-7_200)))
        // Blocks close on them — flag clear, gap closed, tip still stale.
        let closing = settledReading("main", 800_300)
        _ = state.advance(instant: t0.advanced(by: .seconds(10)), reading: closing)
        #expect(
            NodeAutomation.caughtUp(
                reading: closing,
                headersAdvanced: state.headersAdvanced, peers: [], now: watchNow))
    }

    @Test("confirmingPeers counts only block-serving kinds at the exact height")
    func confirmingPeersCounts() throws {
        // Every kind the wire produces, all confirming the same height — plus
        // one qualifying kind at the wrong height. Only the two block-serving
        // kinds at our headers figure count.
        let peers = try [
            peerEvidence(
                connectionType: "outbound-full-relay", inbound: false,
                syncedHeaders: 800_000),
            peerEvidence(
                connectionType: "block-relay-only", inbound: false,
                syncedHeaders: 800_000),
            peerEvidence(connectionType: "inbound", inbound: true, syncedHeaders: 800_000),
            peerEvidence(connectionType: "manual", inbound: false, syncedHeaders: 800_000),
            peerEvidence(connectionType: "feeler", inbound: false, syncedHeaders: 800_000),
            peerEvidence(
                connectionType: "addr-fetch", inbound: false, syncedHeaders: 800_000),
            peerEvidence(
                connectionType: "private-broadcast", inbound: false,
                syncedHeaders: 800_000),
            peerEvidence(connectionType: nil, inbound: false, syncedHeaders: 800_000),
            peerEvidence(
                connectionType: "outbound-full-relay", inbound: false,
                syncedHeaders: 799_999),
        ]
        #expect(NodeAutomation.confirmingPeers(peers, at: 800_000) == 2)
    }

    @Test("the peer quorum is the spec's two confirmations, and an injected floor is honored")
    func peerQuorum() throws {
        #expect(NodeAutomation.peerConfirmationsRequired == 2)
        let peers = try [
            peerEvidence(
                connectionType: "outbound-full-relay", inbound: false,
                syncedHeaders: 800_000),
        ]
        #expect(
            NodeAutomation.caughtUp(
                reading: settledReading(),
                headersAdvanced: false, peers: peers, now: watchNow,
                requiredPeerConfirmations: 1))
        #expect(
            NodeAutomation.caughtUp(
                reading: settledReading(),
                headersAdvanced: false, peers: peers, now: watchNow,
                requiredPeerConfirmations: 3)
                == false)
    }

    @Test("a flat pass with only the peer leg left wants the question")
    func qualifyingPassWantsEvidence() {
        // Flag clear, gap closed, headers never advanced — the cheap legs
        // are spent; peers are the last way a catch-up can be proven.
        #expect(
            NodeAutomation.wantsPeerEvidence(
                reading: settledReading(), headersAdvanced: false))
    }

    @Test("watched growth never asks — the pass already has its leg")
    func grownPassNeverAsks() {
        #expect(
            NodeAutomation.wantsPeerEvidence(
                reading: settledReading(), headersAdvanced: true)
                == false)
    }

    @Test("a set flag never asks — peers cannot certify past it")
    func flaggedPassNeverAsks() {
        #expect(
            NodeAutomation.wantsPeerEvidence(
                reading: reading("main", 800_000, isInitialBlockDownload: true),
                headersAdvanced: false)
                == false)
    }

    @Test("an open gap never asks — the node is still plainly behind")
    func gappedPassNeverAsks() {
        #expect(
            NodeAutomation.wantsPeerEvidence(
                reading: reading("main", 800_000, behind: 200),
                headersAdvanced: false)
                == false)
    }

    // MARK: - Ending precedence

    @Test("a stopped node outranks every other ending — even all of them at once")
    func nodeStoppedOutranksAll() {
        // The pass where everything is true at once: the person stopped the
        // node as the network turned metered, the proof landed, a leash
        // stood already tripped, and the budget ran out.
        #expect(
            NodeAutomation.watchEnding(
                nodeStopped: true, caughtUp: true, conditionsChanged: true,
                noProgress: true, budgetSpent: true) == .nodeStopped)
    }

    @Test("a deliberate stop outranks even a completed catch-up proof")
    func nodeStoppedOutranksCaughtUp() {
        // The proof is terminal truth, but a stopped node leaves nothing to
        // measure — the stop ends measurement itself.
        #expect(
            NodeAutomation.watchEnding(
                nodeStopped: true, caughtUp: true, conditionsChanged: false,
                noProgress: false, budgetSpent: false) == .nodeStopped)
    }

    @Test("a stopped node as the network turns metered reports nodeStopped")
    func nodeStoppedBeatsMetered() {
        // Spec scenario 18: both endings hold on the pass — the deliberate
        // stop is the report, not the drifted condition.
        #expect(
            NodeAutomation.watchEnding(
                nodeStopped: true, caughtUp: false, conditionsChanged: true,
                noProgress: false, budgetSpent: false) == .nodeStopped)
    }

    @Test("a completed proof outranks drifted conditions, a tripped leash, and a spent budget")
    func caughtUpOutranksTheRest() {
        // Terminal truth: conditions that drifted in the same pass are
        // advisory for the next run, not a verdict on one that finished.
        #expect(
            NodeAutomation.watchEnding(
                nodeStopped: false, caughtUp: true, conditionsChanged: true,
                noProgress: true, budgetSpent: true) == .caughtUp)
    }

    @Test("drifted conditions outrank a tripped leash and a spent budget")
    func conditionsChangedOutranksStallAndBudget() {
        #expect(
            NodeAutomation.watchEnding(
                nodeStopped: false, caughtUp: false, conditionsChanged: true,
                noProgress: true, budgetSpent: true) == .conditionsChanged)
    }

    @Test("a tripped leash outranks a spent budget")
    func noProgressOutranksBudget() {
        // Any verdict outranks a spent budget — a node that went quiet
        // reports noProgress, not stillSyncing.
        #expect(
            NodeAutomation.watchEnding(
                nodeStopped: false, caughtUp: false, conditionsChanged: false,
                noProgress: true, budgetSpent: true) == .noProgress)
    }

    @Test("a spent budget alone ends stillSyncing")
    func spentBudgetIsStillSyncing() {
        #expect(
            NodeAutomation.watchEnding(
                nodeStopped: false, caughtUp: false, conditionsChanged: false,
                noProgress: false, budgetSpent: true) == .stillSyncing)
    }

    @Test("each ending alone reports itself")
    func soloEndings() {
        // Every candidacy that can stand alone reports its own ending — the
        // order only arbitrates overlaps.
        #expect(
            NodeAutomation.watchEnding(
                nodeStopped: true, caughtUp: false, conditionsChanged: false,
                noProgress: false, budgetSpent: false) == .nodeStopped)
        #expect(
            NodeAutomation.watchEnding(
                nodeStopped: false, caughtUp: true, conditionsChanged: false,
                noProgress: false, budgetSpent: false) == .caughtUp)
        #expect(
            NodeAutomation.watchEnding(
                nodeStopped: false, caughtUp: false, conditionsChanged: true,
                noProgress: false, budgetSpent: false) == .conditionsChanged)
        #expect(
            NodeAutomation.watchEnding(
                nodeStopped: false, caughtUp: false, conditionsChanged: false,
                noProgress: true, budgetSpent: false) == .noProgress)
    }

    @Test("with nothing holding, the watch keeps going")
    func nothingKeepsWatching() {
        #expect(
            NodeAutomation.watchEnding(
                nodeStopped: false, caughtUp: false, conditionsChanged: false,
                noProgress: false, budgetSpent: false) == nil)
    }

    // MARK: - The bar's fraction and bands

    /// Fractions are asserted against a small tolerance, not bitwise equality:
    /// the band edges (0.10, 0.95) and the multiplied positions between them
    /// are not exact in binary floating point.
    private func approximately(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 0.000_001
    }

    @Test("the fraction is the distance this run closed toward the live tip")
    func syncFractionMeasuresDistanceClosed() {
        // Entered at 800,000, now at 800,050 of a live tip at 800,200: the run
        // closed 50 of the 200 it had remaining — a quarter of the distance.
        #expect(
            approximately(
                NodeAutomation.syncFraction(
                    height: 800_050, baselineHeight: 800_000, liveHeaders: 800_200),
                0.25))
    }

    @Test("the fraction is zero where the run began")
    func syncFractionIsZeroAtEntry() {
        #expect(
            NodeAutomation.syncFraction(
                height: 800_000, baselineHeight: 800_000, liveHeaders: 800_400) == 0)
    }

    @Test("the fraction is one when the height reaches the live tip")
    func syncFractionIsOneAtTheTip() {
        #expect(
            NodeAutomation.syncFraction(
                height: 800_200, baselineHeight: 800_000, liveHeaders: 800_200) == 1)
    }

    @Test("fresh headers grow the denominator — the same gain reads smaller")
    func liveDenominatorShrinksTheFraction() {
        // The tip is re-read each poll, so a denominator that moves mid-watch
        // pulls the true fraction down rather than freezing at entry's size.
        let before = NodeAutomation.syncFraction(
            height: 800_050, baselineHeight: 800_000, liveHeaders: 800_200)
        let after = NodeAutomation.syncFraction(
            height: 800_050, baselineHeight: 800_000, liveHeaders: 800_400)
        #expect(after < before)
    }

    @Test("a reorg below the entry height clamps the numerator at zero")
    func reorgBelowBaselineClampsAtZero() {
        // The height went backwards past where the run started — the run
        // closed nothing, never a negative distance.
        #expect(
            NodeAutomation.syncFraction(
                height: 799_950, baselineHeight: 800_000, liveHeaders: 800_400) == 0)
    }

    @Test("a node that has learned no gap yet reads zero — the floored denominator covers the cold-IBD window")
    func noGapYetReadsZero() {
        // Before the first headers arrive, `headers` still equals the entry
        // height: the denominator floors at one and the bar holds at the band
        // floor rather than dividing by nothing.
        #expect(
            NodeAutomation.syncFraction(
                height: 800_000, baselineHeight: 800_000, liveHeaders: 800_000) == 0)
    }

    @Test("a height past headers reports the raw arithmetic — display clamping is the band's job")
    func heightPastHeadersReportsRaw() {
        // `headers < blocks` cannot come from a real node, but the function
        // reports the arithmetic it was given — more than everything known —
        // rather than silently clamping a measurement the caller may want to
        // see.
        #expect(
            NodeAutomation.syncFraction(
                height: 800_050, baselineHeight: 800_000, liveHeaders: 800_000) == 50)
    }

    @Test("the bands are the spec's start-up ~10% and working ceiling ~95%")
    func bandEdgesAreTheSpecFigures() {
        #expect(NodeAutomation.startUpBandEnd == 0.1)
        #expect(NodeAutomation.watchBandEnd == 0.95)
    }

    @Test("every pre-watch write compresses into the start-up band")
    func startUpBandCompressesWrites() {
        // The milestones and the ramp alike map into the first tenth of the
        // bar — the first-answer plateau's 0.9 lands at ~0.09, and a
        // completion-equivalent 1.0 reaches the band's end, not the full bar.
        #expect(NodeAutomation.startUpBand(0) == 0)
        #expect(approximately(NodeAutomation.startUpBand(0.6), 0.06))
        #expect(approximately(NodeAutomation.startUpBand(0.9), 0.09))
        #expect(approximately(NodeAutomation.startUpBand(1), 0.1))
    }

    @Test("a stray pre-watch write is clamped inside the band")
    func startUpBandClampsStrayWrites() {
        #expect(NodeAutomation.startUpBand(-0.5) == 0)
        #expect(approximately(NodeAutomation.startUpBand(1.5), 0.1))
    }

    @Test("the watch band's floor is where start-up left the bar")
    func watchBandStartsWhereStartUpEnds() {
        // A distance of zero parks the bar at the band floor — the honest
        // display while the node has learned no gap yet.
        #expect(
            approximately(
                NodeAutomation.watchBand(0), NodeAutomation.startUpBandEnd))
    }

    @Test("the watch band's top is the working ceiling, never the full bar")
    func watchBandStopsAtTheCeiling() {
        // A finished distance stops at ~95%: the last stretch is the reserve
        // only an earned ending may fill.
        #expect(approximately(NodeAutomation.watchBand(1), NodeAutomation.watchBandEnd))
        #expect(NodeAutomation.watchBand(1) < 1)
    }

    @Test("the watch fraction sweeps the band in order")
    func watchBandSweepsInOrder() {
        #expect(approximately(NodeAutomation.watchBand(0.5), 0.525))
        #expect(
            NodeAutomation.watchBand(0.25) < NodeAutomation.watchBand(0.5)
                && NodeAutomation.watchBand(0.5) < NodeAutomation.watchBand(0.75))
    }

    @Test("a fraction above one clamps at the ceiling, not past it")
    func watchBandClampsPastOne() {
        // The corrupt-reading fraction `syncFraction` can report lands at the
        // ceiling — "more than everything known" displays as the band's top.
        #expect(approximately(NodeAutomation.watchBand(50), NodeAutomation.watchBandEnd))
    }

    @Test("the assembled chain — a reading's sync fraction lands inside the watch band")
    func fractionFeedsTheWatchBand() {
        // Half the distance closed displays halfway through the band; the
        // cold-IBD window (height and headers still at the entry figure)
        // holds the bar at the band floor.
        #expect(
            approximately(
                NodeAutomation.watchBand(
                    NodeAutomation.syncFraction(
                        height: 800_100, baselineHeight: 800_000, liveHeaders: 800_200)),
                0.525))
        #expect(
            approximately(
                NodeAutomation.watchBand(
                    NodeAutomation.syncFraction(
                        height: 800_000, baselineHeight: 800_000, liveHeaders: 800_000)),
                NodeAutomation.startUpBandEnd))
    }
}
