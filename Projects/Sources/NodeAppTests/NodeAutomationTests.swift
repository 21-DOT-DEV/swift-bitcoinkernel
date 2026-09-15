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

    @Test("the private-network refusal carries the sentence both declining paths share")
    func startRefusalMessage() {
        // Two paths decline for this reason — the deliberate wait-for-it step and
        // the start that finds it gone at the last moment — so the sentence lives
        // on the refusal itself. Pinned here because wording that drifted between
        // them would tell the person two different stories about the same thing.
        let message = NodeAutomation.StartRefusal.privateNetworkNotReady.message
        #expect(message.contains("private network was not ready"))
        #expect(message.contains("being established"))
    }

    // MARK: - Turning readings into a report

    private func reading(_ chain: String, _ height: Int, behind: Int = 0)
        -> NodeAutomation.LiveReading
    {
        NodeAutomation.LiveReading(chain: chain, height: height, blocksBehind: behind)
    }

    @Test("blocks gained is the difference between two readings")
    func blocksGained() {
        #expect(
            NodeAutomation.blocksGained(from: reading("main", 100), to: reading("main", 142)) == 42)
    }

    @Test("blocks gained is unknown when either reading is missing")
    func blocksGainedMissing() {
        #expect(NodeAutomation.blocksGained(from: nil, to: reading("main", 142)) == nil)
        #expect(NodeAutomation.blocksGained(from: reading("main", 100), to: nil) == nil)
    }

    @Test("blocks gained is unknown across different chains, never a nonsense number")
    func blocksGainedAcrossChains() {
        // Subtracting a test-chain height from a main-chain one would produce a
        // confident-looking lie.
        #expect(
            NodeAutomation.blocksGained(from: reading("test", 10), to: reading("main", 900_000))
                == nil)
    }

    @Test("a height that went backwards reports no gain rather than a negative one")
    func blocksGainedNeverNegative() {
        #expect(
            NodeAutomation.blocksGained(from: reading("main", 200), to: reading("main", 150)) == 0)
    }

    @Test("a declined run reports its reason as the whole message")
    func summaryDeclined() {
        let text = NodeAutomation.summary(
            outcome: .declined, chain: "main", height: 5, blocksBehind: nil,
            blocksSinceLastCheck: nil, declinedReason: "Low Power Mode is on.")
        #expect(text == "Low Power Mode is on.")
    }

    @Test("a run whose node never answered says nothing was measured")
    func summaryDidNotComeUp() {
        let text = NodeAutomation.summary(
            outcome: .didNotComeUp, chain: "main", height: 5, blocksBehind: nil,
            blocksSinceLastCheck: nil, declinedReason: nil)
        #expect(text.contains("had not come up"))
        #expect(text.contains("nothing was measured"))
    }

    @Test("a run that got no usable answer says nothing was measured")
    func summaryNoAnswer() {
        // Covers both ways a run ends here — a node that never answered, and an
        // answer discarded because the node was stopped or the run ended while the
        // question was in flight. Either way, nothing usable was measured.
        let text = NodeAutomation.summary(
            outcome: .noAnswer, chain: "main", height: 5, blocksBehind: nil,
            blocksSinceLastCheck: nil, declinedReason: nil)
        #expect(text.contains("did not answer"))
        #expect(text.contains("nothing was measured"))
        // It must not imply the node was started — on this path it may already have
        // been running.
        #expect(text.contains("started") == false)
    }

    @Test("a started run names the chain, the height, and what arrived since")
    func summaryStarted() {
        let text = NodeAutomation.summary(
            outcome: .started, chain: "main", height: 900_000, blocksBehind: 12,
            blocksSinceLastCheck: 3, declinedReason: nil)
        #expect(text.contains("main"))
        // The height is formatted through the device's locale ("900,000" in en_US).
        // Expecting it via formatted() keeps the test true in every locale while
        // still failing if the code ever interpolates the raw number instead.
        #expect(text.contains(900_000.formatted()))
        #expect(text.contains("12 behind"))
        #expect(text.contains("3 new blocks"))
    }

    @Test("being caught up omits the behind-count instead of saying zero behind")
    func summaryCaughtUp() {
        let text = NodeAutomation.summary(
            outcome: .started, chain: "main", height: 900_000, blocksBehind: 0,
            blocksSinceLastCheck: nil, declinedReason: nil)
        #expect(text.contains("behind") == false)
    }

    @Test("no new blocks is stated, and is not the same as not knowing")
    func summaryZeroVersusUnknownGain() {
        let measuredZero = NodeAutomation.summary(
            outcome: .started, chain: "main", height: 10, blocksBehind: nil,
            blocksSinceLastCheck: 0, declinedReason: nil)
        let notMeasured = NodeAutomation.summary(
            outcome: .started, chain: "main", height: 10, blocksBehind: nil,
            blocksSinceLastCheck: nil, declinedReason: nil)
        #expect(measuredZero.contains("No new blocks"))
        #expect(notMeasured.contains("No new blocks") == false)
        #expect(measuredZero != notMeasured)
    }

    @Test("one new block reads as singular")
    func summarySingularBlock() {
        let text = NodeAutomation.summary(
            outcome: .started, chain: "main", height: 10, blocksBehind: nil,
            blocksSinceLastCheck: 1, declinedReason: nil)
        #expect(text.contains("1 new block since"))
    }

    @Test("an already-running node is reported as found, not started")
    func summaryAlreadyRunning() {
        let text = NodeAutomation.summary(
            outcome: .alreadyRunning, chain: "main", height: 7, blocksBehind: nil,
            blocksSinceLastCheck: nil, declinedReason: nil)
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
}
