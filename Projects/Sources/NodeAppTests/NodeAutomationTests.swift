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
    private static func decodePeer(connectionType: String?, inbound: Bool) throws -> PeerInfo {
        let connField = connectionType.map { "\"connection_type\":\"\($0)\"," } ?? ""
        return try JSONDecoder().decode(
            PeerInfo.self,
            from: Data(
                """
                {"id":0,"addr":"10.0.0.1:8333","services":"0000000000000409","relaytxes":true,
                 "lastsend":1713300000,"lastrecv":1713300000,"bytessent":1000,"bytesrecv":2000,
                 "conntime":1713200000,"timeoffset":0,"version":70016,"subver":"/Satoshi:31.0.0/",
                 \(connField)"inbound":\(inbound),"synced_headers":876000,"synced_blocks":876000}
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
                outcome: .declined, chain: "main", height: 5, blocksBehind: nil,
                blocksSinceLastCheck: nil, declinedReason: "Low Power Mode is on."))
        #expect(text == "Low Power Mode is on.")
    }

    @Test("a run that found the node still coming up says nothing was measured")
    func summaryDidNotComeUp() {
        let text = String(
            localized: NodeAutomation.summary(
                outcome: .didNotComeUp, chain: "main", height: 5, blocksBehind: nil,
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
                outcome: .noAnswer, chain: "main", height: 5, blocksBehind: nil,
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
                outcome: .started, chain: "main", height: 900_000, blocksBehind: 12,
                blocksSinceLastCheck: 3, declinedReason: nil))
        // The node's "main" wire name is mapped to the display name before a
        // person reads it.
        #expect(text.contains("Mainnet"))
        // The count interpolates as a raw Int (%lld), which the resolver renders
        // with the locale's digit grouping — "900,000" in en_US — so asserting
        // the grouped figure still fails if the code ever strings the number
        // through a fixed-locale formatter instead.
        #expect(text.contains(900_000.formatted()))
        #expect(text.contains("12 behind"))
        #expect(text.contains("3 new blocks"))
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
                    outcome: .started, chain: wire, height: 10, blocksBehind: nil,
                    blocksSinceLastCheck: nil, declinedReason: nil))
            #expect(text.contains("on \(display)"))
        }
        // A name the code does not recognise — a newer network, a fork — is
        // shown verbatim rather than dropped or mislabeled.
        let unknown = String(
            localized: NodeAutomation.summary(
                outcome: .started, chain: "scalenet", height: 10, blocksBehind: nil,
                blocksSinceLastCheck: nil, declinedReason: nil))
        #expect(unknown.contains("scalenet"))
        // "testnet4" is the tempting mislabel: *a* testnet, but not the
        // "Testnet" the settings picker offers — verbatim is honest.
        let testnet4 = String(
            localized: NodeAutomation.summary(
                outcome: .started, chain: "testnet4", height: 10, blocksBehind: nil,
                blocksSinceLastCheck: nil, declinedReason: nil))
        #expect(testnet4.contains("testnet4"))
        #expect(testnet4.contains("Testnet ") == false)
    }

    @Test("being caught up omits the behind-count instead of saying zero behind")
    func summaryCaughtUp() {
        let text = String(
            localized: NodeAutomation.summary(
                outcome: .started, chain: "main", height: 900_000, blocksBehind: 0,
                blocksSinceLastCheck: nil, declinedReason: nil))
        #expect(text.contains("behind") == false)
    }

    @Test("no new blocks is stated, and is not the same as not knowing")
    func summaryZeroVersusUnknownGain() {
        let measuredZero = String(
            localized: NodeAutomation.summary(
                outcome: .started, chain: "main", height: 10, blocksBehind: nil,
                blocksSinceLastCheck: 0, declinedReason: nil))
        let notMeasured = String(
            localized: NodeAutomation.summary(
                outcome: .started, chain: "main", height: 10, blocksBehind: nil,
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
                outcome: .started, chain: "main", height: 10, blocksBehind: nil,
                blocksSinceLastCheck: 1, declinedReason: nil))
        #expect(text.contains("1 new block since"))
    }

    @Test("an already-running node is reported as found, not started")
    func summaryAlreadyRunning() {
        let text = String(
            localized: NodeAutomation.summary(
                outcome: .alreadyRunning, chain: "main", height: 7, blocksBehind: nil,
                blocksSinceLastCheck: nil, declinedReason: nil))
        #expect(text.contains("already running"))
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
        #expect(NodeAutomation.ending(outcome: .started, summary: "x").fillsProgressBar)
        #expect(NodeAutomation.ending(outcome: .alreadyRunning, summary: "x").fillsProgressBar)
        #expect(
            NodeAutomation.ending(outcome: .declined, summary: "x").fillsProgressBar == false)
        #expect(
            NodeAutomation.ending(outcome: .didNotComeUp, summary: "x").fillsProgressBar
                == false)
        #expect(
            NodeAutomation.ending(outcome: .noAnswer, summary: "x").fillsProgressBar
                == false)
    }

    @Test("the card's detail line is the run's own summary sentence")
    func endingCarriesTheSummary() {
        // The summary is the one piece of text in the feature written to be read by a
        // person; the card must not paraphrase it into something that could disagree.
        let sentence = "Low Power Mode is on, so the node did not start."
        #expect(NodeAutomation.ending(outcome: .declined, summary: sentence).detail == sentence)
    }

    @Test("every ending has a headline, and they tell the five apart")
    func endingTitles() {
        let titles = [
            NodeAutomation.ending(outcome: .started, summary: "x").title,
            NodeAutomation.ending(outcome: .alreadyRunning, summary: "x").title,
            NodeAutomation.ending(outcome: .declined, summary: "x").title,
            NodeAutomation.ending(outcome: .didNotComeUp, summary: "x").title,
            NodeAutomation.ending(outcome: .noAnswer, summary: "x").title,
        ]
        #expect(titles.allSatisfy { $0.isEmpty == false })
        #expect(Set(titles).count == titles.count)
    }

    @Test("a run that was refused does not describe itself as running")
    func endingDeclinedDoesNotClaimRunning() {
        let declined = NodeAutomation.ending(outcome: .declined, summary: "x").title
        let didNotComeUp = NodeAutomation.ending(outcome: .didNotComeUp, summary: "x").title
        let noAnswer = NodeAutomation.ending(outcome: .noAnswer, summary: "x").title
        #expect(declined.contains("running") == false)
        #expect(didNotComeUp.contains("running") == false)
        #expect(noAnswer.contains("running") == false)
    }

    @Test("the in-progress headline is set")
    func inProgressTitleExists() {
        #expect(NodeAutomation.inProgressTitle.isEmpty == false)
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
}
