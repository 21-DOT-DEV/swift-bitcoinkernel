//
//  NodeRun.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Bitcoin
import Foundation
import os.log

// Phone and tablet only, for the reason recorded in
// Development/Specs/003-node-automation-action/plan.md §2.
#if os(iOS)

import UIKit

/// The session a run sees: the process-owned node and private-network
/// controllers, the connection it asks questions through, and the device
/// readings its conditions gathers consult.
///
/// `NodeSession.shared` is the only production conformer — its members forward
/// to `NodeViewModel` and `TorViewModel`. The seam exists so a test can drive
/// `perform` against states a real `NodeSession` cannot be put into — a
/// private network that never readies, or a node that stops mid-question —
/// because its node and Tor state are read-only views of live controllers.
/// The surface is deliberately the flat list of facts the run consults rather
/// than the controllers' own shapes: a run asks "is the node still up" and "is
/// the private network usable", never "is a view-model flag set".
@MainActor
protocol RunSession {

    /// The node's lifecycle state, re-read each time it is consulted: a run
    /// watches for a stopped node coming up — and for a running one going
    /// down — while it waits.
    var nodeState: NodeState { get }

    /// Whether the private network is usable right now — bootstrapped and
    /// holding a SOCKS endpoint — rather than merely switched on.
    var torIsReady: Bool { get }

    /// Whether the private network is still on its way to usable inside
    /// `horizon` — bootstrapping, retrying a failed attempt inside its
    /// backoff schedule, or finishing a teardown that carries a queued
    /// restart. The horizon is the waiter's own remaining budget: a failed
    /// network whose next scheduled attempt lands beyond it reads `false`
    /// too, so a wait gives up on a Tor that cannot arrive in time instead
    /// of holding its whole budget — while the teardown leg ignores it,
    /// since teardowns are prompt and the wait's other exits still bound
    /// the outcome. The retry comparison runs on the wall clock, matching
    /// the schedule's basis; `TorViewModel.isComingUp(within:)` spells out
    /// what that means under a virtual clock. An attempt already in flight
    /// — or a retry firing now — always reads `true`: its arrival is not
    /// schedulable, only its abandonment would be premature.
    func torIsComingUp(within horizon: Duration) -> Bool

    /// The private network's `host:port` SOCKS address, handed to the node's
    /// arguments only while `torIsReady` holds.
    var torProxyAddress: String? { get }

    /// The private-network session identifier passed to the node start, so
    /// the daemon's lifecycle can be tied to the Tor session that spawned it.
    var torSessionID: UUID? { get }

    /// The SOCKS port the node is started against when privacy is required.
    var torSocksPort: UInt16? { get }

    /// The connection the run asks questions through — which chain, what
    /// height, how many peers.
    var reader: any DashboardDataSource { get }

    /// The device the run's conditions gathers read — protected data, power,
    /// heat, disk, network cost. The raw readings only; how they combine into
    /// a gather's answer stays in `NodeRun`, where a scripted adapter can
    /// watch them be used.
    var device: any DeviceReadings { get }

    /// Whether the node's questions are currently served by the direct
    /// in-process bridge — `true` means an answer is bounded by the bridge's
    /// own ~30 s give-up (uncancellable: an abandoned call finishes in the
    /// background), `false` means the ~60 s `URLSession` ceiling (the one
    /// transport `withHardTimeout`'s cancel genuinely terminates). Re-read
    /// per question so the run's log attributes every answer's timing to
    /// the ceiling it was measured under — on a fast-starting node the
    /// bridge can flip mid-run.
    var bridgeReady: Bool { get }

    /// Starts the node with the given daemon arguments.
    ///
    /// - Returns: whether the start was accepted. The concrete node refuses
    ///   anything but `.stopped`, so `false` means the state moved under the
    ///   run — another run, the app's own Start button, or a restart.
    func startNode(arguments: [String], torSession: UUID?, torSocksPort: UInt16?) -> Bool

    /// Starts the private network only if its setting is still on right now.
    ///
    /// - Parameter defaults: the store the still-on check reads — the same one
    ///   the run's snapshot came from, so a test's throwaway store is the
    ///   setting this method consults too.
    /// - Returns: whether the setting is still on. The wait-for-it path uses
    ///   it to word the decline honestly — "being established now" is only
    ///   true while the network is actually wanted.
    @discardableResult
    func startTorIfStillEnabled(reading defaults: UserDefaults) -> Bool
}

/// The raw device readings a run's conditions gathers ask for.
///
/// One member per system call — no decision lives here. Which readings a
/// gather asks for, in what order, and how long the network answer may wait
/// stay in `NodeRun`, where a scripted adapter can watch them be used.
/// `LiveDeviceReadings` is the production conformer: every one of its lines
/// touches an Apple framework or the filesystem, none of which can be
/// exercised by automated checks — which is why the type exists and why it
/// contains nothing else.
@MainActor
protocol DeviceReadings: Sendable {

    /// Ensures the network-cost watcher is running, so the reads below have
    /// an answer ready. Idempotent — the watcher, once started, is never
    /// stopped.
    func startWatchingNetworkCost()

    /// Whether protected data is readable — false only before the first
    /// unlock after a restart.
    var protectedDataAvailable: Bool { get }

    /// Whether Low Power Mode is on.
    var lowPowerModeEnabled: Bool { get }

    /// The system's thermal pressure.
    var thermalState: ProcessInfo.ThermalState { get }

    /// Creates the chain folder if needed — a write, so a gather attempts it
    /// only after finding files readable — reporting whether it is there.
    func prepareChainFolder() -> Bool

    /// Free space for important work on the chain volume, or `nil` if the
    /// system could not say.
    func freeDiskBytes() -> Int64?

    /// The network's first cost report, waiting for it — deliberately
    /// unbounded here: how long it may wait is the caller's call, bounded on
    /// the run's own clock where a test can drive it.
    ///
    /// `nonisolated` because its only caller is a `withHardTimeout`
    /// operation — a detached task kept off every actor on purpose — and the
    /// monitor's own poll is actor-free beneath it. A `@MainActor` member
    /// would make the one wait that stays off the main actor hop through it.
    nonisolated func networkFirst() async -> NetworkCost

    /// The latest network-cost answer without waiting — `.unknown` until the
    /// watcher has reported. Nothing reads it yet: it exists for T024's
    /// mid-watch drift check, which re-weighs conditions on a change the
    /// first-report wait cannot see.
    var networkCurrent: NetworkCost { get }
}

/// The production `DeviceReadings`: each member forwards one system call and
/// nothing more — the seam exists precisely because these lines are the ones
/// no test can drive.
@MainActor
struct LiveDeviceReadings: DeviceReadings {

    private static let log = Logger(subsystem: "dev.21.NodeApp", category: "Shortcut")

    func startWatchingNetworkCost() {
        NetworkCostMonitor.shared.start()
    }

    var protectedDataAvailable: Bool {
        UIApplication.shared.isProtectedDataAvailable
    }

    var lowPowerModeEnabled: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var thermalState: ProcessInfo.ThermalState {
        ProcessInfo.processInfo.thermalState
    }

    /// The request to keep the folder out of backups is best-effort inside
    /// `DaemonConfig.prepareDataDirectory` — a folder that exists but is
    /// unmarked is perfectly writable, and unattended there is nobody to
    /// notice backups growing, which is why that failure is only ever logged.
    func prepareChainFolder() -> Bool {
        do {
            try DaemonConfig.prepareDataDirectory(at: DaemonConfig.dataDirectory)
            return true
        } catch {
            Self.log.error(
                "run: chain folder could not be prepared — \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Free space measured on the chain folder's volume as the figure the
    /// system reports for *important* work rather than raw free bytes — a
    /// courtesy reading, since the system may not reclaim it in time.
    func freeDiskBytes() -> Int64? {
        let url = DaemonConfig.dataDirectory
        guard
            let values = try? url.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey
            ]),
            let capacity = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return capacity
    }

    nonisolated func networkFirst() async -> NetworkCost {
        await NetworkCostMonitor.shared.first()
    }

    var networkCurrent: NetworkCost {
        NetworkCostMonitor.shared.current
    }
}

/// The one routine both Shortcuts actions call, so their behaviour cannot drift apart.
///
/// Everything here touches the device or the node, which is why it cannot be exercised
/// by automated checks; the decisions it makes live in `NodeAutomation` and
/// `NodePreflight`, which are plain values and are tested. This orchestrates and does
/// no deciding. See `Development/Specs/003-node-automation-action/plan.md` §3.
@MainActor
enum NodeRun {

    private static let log = Logger(subsystem: "dev.21.NodeApp", category: "Shortcut")

    /// The tolerance attached to the run's cadence sleeps — today only the
    /// iOS 27 action's heartbeat — so the system may coalesce them with other
    /// work. Sleeps that bound a deadline keep `tolerance: nil`: the races
    /// inside `withHardTimeout`, and the wait loop's deadline-capped nap —
    /// a sleep meant to bound a deadline must not be permitted to outlive it.
    static let sleepTolerance: Duration = .seconds(1)

    /// The most a single question to the node may take before the run stops
    /// waiting on it.
    ///
    /// The channel used to ask the node a question waits up to thirty seconds
    /// for an answer and cannot be cancelled once asked — it runs to completion
    /// in-process. Left unbounded, one slow question consumes a whole run: the
    /// short action has roughly thirty seconds in total, and roughly thirty
    /// seconds without a progress report is what it takes for the system to end
    /// an extended run as stalled. `withHardTimeout` makes the bound real — the
    /// abandoned question finishes in the background and its answer is dropped.
    /// Ten seconds is a judgment call: long enough that a healthy node answers
    /// comfortably, short enough that the short action's read of an
    /// already-running node (two questions) still fits its window.
    private static let questionBudget: Duration = .seconds(10)

    /// The most a single question may take on a run carrying a watch
    /// budget — thirty seconds, the watch's own patience and the daemon's
    /// own `-rpcservertimeout` cutoff over HTTP. That figure matches the
    /// direct bridge's own give-up rather than beating it, so the bound
    /// and the channel race on the direct path — a coin flip between two
    /// identical `nil`s, the abandoned call finishing in the background
    /// either way. A budgeted run bounds
    /// *every* question here, the first-answer wait included, because all
    /// of them share the same contention: `getblockchaininfo` and
    /// `getnetworkinfo` alike ride the daemon's main thread (`cs_main`),
    /// which IBD can bury for the whole of the short action's window. A
    /// run that can afford a fifteen-minute watch would otherwise write a
    /// slow-but-alive ~11 s node off before the watch could begin — the
    /// 10 s bound above is shaped for the short action's window, where
    /// that answer is slow rather than dead.
    private static let watchQuestionBudget: Duration = .seconds(30)

    /// The watch's poll cadence — about five seconds between passes
    /// (FR-001). The loop is sequential — a pass asks its question, then
    /// naps — so a question that runs to its bound stretches that pass to
    /// `questionBound + cadence`: it delays the next pass, never cancels
    /// it, and the leashes measure wall time rather than pass counts, so
    /// the stretch spends budget, not correctness. The nap carries the
    /// run's shared tolerance whenever enough budget remains to absorb a
    /// coalesced wake — a cadence the system may coalesce, not a deadline
    /// bound like the waits' naps.
    private static let watchPollInterval: Duration = .seconds(5)

    /// One report of where the run's progress display should sit.
    ///
    /// The bar's position today — `fraction` — plus the two lines of card
    /// text the sync watch reports alongside it: `headline` and `detail`
    /// are `nil` until the watch commits, then carried on every pass
    /// (T030 writes them to the display; only the watch produces them).
    /// Text travels as an unresolved resource for the same reason
    /// `NodeRunReport.dialogTemplate` does: the sentence is decided where
    /// the facts are and resolved where it is shown.
    struct ProgressUpdate: Sendable, Equatable {

        /// How far through the run this report places the bar, from 0 to 1.
        let fraction: Double

        /// A replacement headline for the card — `nil` while no write
        /// carrying text has run.
        let headline: LocalizedStringResource?

        /// A replacement detail line — `nil` for the same reason as
        /// `headline`.
        let detail: LocalizedStringResource?

        init(
            fraction: Double,
            headline: LocalizedStringResource? = nil,
            detail: LocalizedStringResource? = nil
        ) {
            self.fraction = fraction
            self.headline = headline
            self.detail = detail
        }
    }

    /// Runs once and reports.
    ///
    /// - Parameters:
    ///   - session: the session the run asks — node state, private-network
    ///     readiness, the connection it asks questions through, and the device
    ///     readings its conditions gathers consult. `NodeSession.shared` in
    ///     production; the `RunSession` seam exists so a test can drive states
    ///     the real session cannot be put into. Passed explicitly so the
    ///     dependency stays visible at the call site rather than baked into
    ///     the signature.
    ///   - waitForFirstAnswer: how long to keep asking the node whether it is up
    ///     after this run starts one — or finds one already starting. The two
    ///     actions pass different budgets: the short-run action has roughly half
    ///     a minute in total and passes a minimal budget — a locked phone has
    ///     been measured taking minutes to load the block index, so waiting for
    ///     it is not a service the short window can provide — while the iOS 27
    ///     action may run for minutes. A wait that runs out is an expected
    ///     outcome, not an error. Only the waiting paths consult this: a node
    ///     that is already answering is read straight away, each question
    ///     bounded by the run's question bound (`questionBudget`, or the
    ///     wider `watchQuestionBudget` on a budgeted run).
    ///   - privateNetworkGrace: the most the run will spend waiting for the
    ///     private network to establish, when the run requires it — the
    ///     snapshot's privacy setting, or a live requirement the launch
    ///     boundary measured mid-run — and it is not yet usable (FR-013).
    ///     `nil` keeps the original verdict — nudge the network and decline
    ///     on the spot — which is the short action's shape: its ~30 s window
    ///     cannot afford a cold bootstrap. The budget is spent once per run:
    ///     whatever ends the wait, the run re-decides on live facts — node
    ///     state, conditions, the step — and a second wait-for-the-network
    ///     verdict declines rather than buying another wait with the same
    ///     money. A non-`nil` grace — or a non-`nil` `syncBudget` — also
    ///     marks the run as budgeted for progress purposes: every
    ///     fraction `onProgress` receives is compressed into
    ///     `NodeAutomation.startUpBand` (`0...0.1`) so the watch stage has
    ///     room to climb — the coupling T030's real flag replaces. Even
    ///     at `nil`, a stall the launch boundary measured
    ///     still routes through the re-decision — one extra conditions
    ///     gather (at most ~2 s of the short action's window) so the report
    ///     can carry the operative refusal — a device condition that
    ///     turned refusing mid-flight — rather than the privacy sentence
    ///     it displaced.
    ///   - syncBudget: the most the run will watch a committed sync before
    ///     ending `stillSyncing` — the watch stage's hard bound — or `nil`
    ///     for a run that reports once it has its answer, the short
    ///     action's contract. Its presence decides three things: every
    ///     question's bound widens to `watchQuestionBudget` (the patience
    ///     a budgeted run can afford), the landing consults the watch's
    ///     entry gate once, and the run joins `privateNetworkGrace` in
    ///     marking the run budgeted *for progress purposes* — the union
    ///     `progress` is keyed on, and the coupling T030's real flag
    ///     replaces.
    ///   - clock: the time source every wait, question bound, and deadline in
    ///     the run is measured on. Generic over `Clock<Duration>` rather than
    ///     `any` so instants stay `Comparable` — the erased `InstantProtocol`
    ///     an existential yields cannot be put in deadline order. Production
    ///     passes `ContinuousClock()`; tests drive the whole run on a
    ///     `ManualClock` (SharedTests).
    ///   - now: the wall-clock instant read each time a decision weighs tip
    ///     age — staged here for the sync watch, whose tip-freshness leg
    ///     re-reads it on every pass. No caller consumes it until that stage
    ///     lands.
    ///   - defaults: the store the run reads its settings snapshot, its live
    ///     privacy-floor check, and the `last_run_*` baseline from. No default
    ///     — a hosted test bundle shares the app's settings domain, so a test
    ///     that forgot the argument would read the person's real
    ///     `tor_enabled` and could send the run down the private-network
    ///     path; the same reason the persistence boundary's `into:` has none.
    ///     Tests pass a volatile suite.
    ///   - onProgress: called as the wait proceeds, each call carrying a
    ///     `ProgressUpdate` — the bar's fraction today, the card's text once
    ///     the watch stage produces it. Fractions arrive on one scale per
    ///     run: raw `0...1` positions while the run carries neither
    ///     `privateNetworkGrace` nor `syncBudget`, or compressed into the
    ///     start-up band (`0...0.1`) when it carries either — see the
    ///     grace parameter.
    ///     The iOS 27 action forwards this to its progress display; advancing it
    ///     is also what keeps that longer time window open. Never call it from
    ///     inside a `withHardTimeout` operation: an abandoned question outlives
    ///     the run, so a report written there can land after `perform` has
    ///     returned and the progress display it feeds is already gone.
    static func perform<C: Clock<Duration>>(
        session: any RunSession,
        waitForFirstAnswer: Duration,
        privateNetworkGrace: Duration? = nil,
        syncBudget: Duration? = nil,
        clock: C,
        now: @escaping @Sendable () -> Date = { Date() },
        defaults: UserDefaults,
        onProgress: @escaping @MainActor (ProgressUpdate) -> Void = { _ in }
    ) async -> NodeRunReport {
        // Every setting the run is allowed to see is read once, here, before the
        // first suspension point: a run spans tens of seconds, and a toggle
        // landing in that window must not rewrite what it launches — a changed
        // `bitcoin_network` would start a chain the launch decision below never
        // covered, and a changed `tor_enabled` would decide privacy on intent
        // the person has already reversed. Screens keep reading live; a run
        // sees this snapshot.
        //
        // One deliberate exception: the privacy *floor* is re-read at the
        // launch boundary in `start` — the only read of a live setting this
        // file makes. A toggle flipped *on* mid-run must never be answered
        // with a direct connection (that direction leaks the person's
        // address), while a toggle flipped *off* after the snapshot required
        // privacy still requires it — a decline is recoverable and a leak is
        // not. See `start` and ADR 0006.
        let settings = DaemonConfig.Snapshot(reading: defaults)
        // The step decision weighs the snapshot's privacy setting; `start`
        // tightens it to snapshot-or-live at the launch boundary — the two
        // deliberately differ, so this local keeps the narrower name.
        let snapshotPrivacy = settings.torEnabled
        log.notice("run: entered, snapshot says privacy network enabled = \(snapshotPrivacy, privacy: .public)")

        // A cancelled task still runs until it checks — a run called off before
        // it began would otherwise launch the node (or the private network) on
        // its way out, the very act the cancel was meant to prevent. Check
        // before the side effects, not just before the reports: here on entry,
        // at the top of every loop pass, and again right before the switch,
        // because the device-condition read in between is the one stretch
        // that suspends (its bounded wait on the first network report).
        guard !Task.isCancelled else { return noAnswerReport() }

        // Idempotent, and belt-and-braces: the watcher is started at process launch, but
        // this is the one path that runs with no window, so it does not rely on that.
        session.device.startWatchingNetworkCost()

        // The grace buys the run one bounded wait for the private network —
        // `nil` is the short action's shape, which declines on the spot. The
        // wait is the only thing this loop re-decides around: whatever ends
        // it, the step, node state, and conditions are weighed again on live
        // facts rather than resuming the path the run left, because ninety
        // seconds is long enough for the person to have started or stopped
        // the node and for the network to have finished or failed for good
        // (plan §3.8). The budget is consumed on use — a second
        // wait-for-the-network verdict declines below rather than buying
        // another wait with the same money — so the loop cannot wait forever.
        var grace = privateNetworkGrace
        // The loop's other re-entry, and the marker that keeps it honest: a
        // launch can reach the boundary — `start`'s one live read — and find
        // the network gone even though the step committed, or find a privacy
        // toggle flipped *on* mid-run that the snapshot-pure step cannot
        // express. Retrying the identical step would never change that
        // verdict, so the refusal returns here as a measured requirement:
        // the step below then reads the run as the wait-for-the-network case
        // it is — where the nudge, the grace, and the unchanged decline all
        // live. Set once, it stays set — a requirement the boundary measured
        // does not un-measure while the run continues — and honored once: a
        // second stall declines the unchanged verdict rather than buying
        // another trip, so every `continue` below is fired by a one-shot
        // marker (the grace, this flag) and the loop is bounded by
        // construction, not by reasoning about which step follows which.
        var networkStalled = false
        // Two implications resolved once, here — the `InitParameterInteraction`
        // rule: nothing downstream re-derives them. The budgeted union is
        // what bands the run's writes (a grace or a budget marks it — the
        // placeholder T030's real flag replaces); `syncBudget` alone is
        // what widens the question bound and admits the watch — a grace
        // without a budget waits for a network, not for a sync.
        let budgeted = privateNetworkGrace != nil || syncBudget != nil
        let questionBound = syncBudget == nil ? questionBudget : watchQuestionBudget
        // `startUpBand`'s documented single application point: a budgeted
        // run wraps the run's whole callback once, so every pre-watch
        // write — the grace's ramp, the fixed milestones, the first-answer
        // ramp — lands inside `0 ... startUpBandEnd` on one scale and no
        // second wrap can double-band it. An unbudgeted run keeps the full
        // bar: with no watch to leave room for, its writes keep their raw
        // positions (the doc's "an unbudgeted run never calls it"). The
        // watch's own writes take `onProgress` unwrapped — band positions
        // already, not stage fractions (FR-004).
        let progress: @MainActor (ProgressUpdate) -> Void =
            !budgeted
            ? onProgress
            : { update in
                onProgress(ProgressUpdate(
                    fraction: NodeAutomation.startUpBand(update.fraction),
                    headline: update.headline,
                    detail: update.detail))
            }
        while true {
            // Every pass checks: a cancelled run pays at most the in-flight
            // stretch — never another gather, never another start attempt.
            guard !Task.isCancelled else { return noAnswerReport() }
            let step = NodeAutomation.step(
                nodeState: session.nodeState,
                privacyEnabled: snapshotPrivacy || networkStalled,
                privacyReady: session.torIsReady
            )

            if NodeAutomation.consultsDeviceConditions(for: step),
                let refusal = NodePreflight.refusal(
                    for: await readConditions(device: session.device, clock: clock))
            {
                log.notice("run: declined — \(String(describing: refusal), privacy: .public)")
                return declined(reason: refusal.message)
            }

            // The second checkpoint promised above: the device-condition read can
            // spend up to two seconds suspended — plenty of window for a stop to
            // arrive. Without this, a called-off run could still reach the branch
            // that starts the private network, and a consensus download over
            // whatever link is current is precisely the act these checks exist to
            // prevent.
            guard !Task.isCancelled else { return noAnswerReport() }

            switch step {
            case .reportExistingNode:
                // Never interrupt a node someone started themselves: read it and leave it
                // alone (ADR 0005).
                log.notice("run: a node is already running — reading and leaving it alone")
                return await report(
                    session: session, syncBudget: syncBudget,
                    questionBound: questionBound, clock: clock, now: now,
                    defaults: defaults, onProgress: progress,
                    watchProgress: onProgress)

            case .waitForStartingNode:
                // Already on its way up: nothing to start, and nothing to read until
                // its block index loads — so the run waits on it exactly like a node
                // it started itself. The step skipped preflight, so the weigh-in is
                // owed at the watch (FR-012).
                log.notice("run: a node is already starting — waiting on it")
                return await waitForStarting(
                    session: session, within: waitForFirstAnswer,
                    syncBudget: syncBudget, weighInOnEntry: true,
                    questionBound: questionBound,
                    clock: clock, now: now, defaults: defaults,
                    onProgress: progress, watchProgress: onProgress)

            case .waitForPrivateNetwork:
                // The step was decided before the device-condition read, which can
                // suspend for seconds — long enough for an in-flight bootstrap to
                // finish. A network that is ready now means there is nothing to
                // wait for, and declining "not ready" would be a lie at report
                // time; take the start path and let its own checks run.
                if session.torIsReady {
                    do {
                        return try await start(
                            session: session, settings: settings, defaults: defaults,
                            waitForFirstAnswer: waitForFirstAnswer,
                            syncBudget: syncBudget, questionBound: questionBound,
                            clock: clock, now: now,
                            onProgress: progress, watchProgress: onProgress)
                    } catch let refusal {
                        // A not-ready refusal — the only thing `start` throws —
                        // routed, not retried: a real stall marks the boundary's
                        // measured requirement so the next pass lands on the
                        // wait-or-decline below; anything else declines as the
                        // boundary ruled, and so does a second stall — the
                        // marker is spent once. The stall arm is unreachable
                        // *here*: the branch above just read `torIsReady`
                        // true, and that read, the boundary's, and this
                        // catch's are one actor stretch — a stall needs the
                        // network gone. The uniform shape stands so a future
                        // suspension inserted inside `start` lands a real
                        // stall on the same routing, not on a silent
                        // one-off decline.
                        guard !networkStalled,
                            isPrivateNetworkStall(refusal, session: session)
                        else { return declined(reason: refusal.message) }
                        networkStalled = true
                        continue
                    }
                }
                // Spend the run establishing the private network rather than starting on a
                // direct connection, which would expose the person's home network address
                // after they asked it not to. Which sentence the person gets — and the
                // log — depends on the live setting: still on means the network is
                // genuinely coming up; switched off mid-run means nothing is being
                // established, and saying so would be a lie in both places.
                let stillEnabled = session.startTorIfStillEnabled(reading: defaults)
                if stillEnabled, let budget = grace {
                    grace = nil   // spent — a second verdict declines below
                    log.notice("run: private network not ready — waiting inside the grace")
                    guard await awaitPrivateNetwork(
                        session: session, within: budget, clock: clock,
                        onProgress: progress)
                    else { return noAnswerReport() }
                    // Whatever ended the wait, the next pass decides on what
                    // is true now — never resume where the run left off.
                    continue
                }
                if stillEnabled {
                    log.notice("run: private network not ready — started it, not starting the node")
                } else {
                    log.notice("run: private network was turned off mid-run — not starting the node")
                }
                return declined(
                    reason: NodeAutomation.StartRefusal(stillEnabled: stillEnabled).message)

            case .startNode:
                do {
                    return try await start(
                        session: session, settings: settings, defaults: defaults,
                        waitForFirstAnswer: waitForFirstAnswer,
                        syncBudget: syncBudget, questionBound: questionBound,
                        clock: clock, now: now,
                        onProgress: progress, watchProgress: onProgress)
                } catch let refusal {
                    // The launch boundary found the network gone after the
                    // step committed — a stall routed so every "not ready"
                    // verdict lands on the same wait-or-decline path above
                    // rather than declining out of order. Retrying this step
                    // unchanged could never change that verdict — it is the
                    // one the marker exists to rewrite — and a second stall
                    // declines here: the marker is spent once.
                    guard !networkStalled,
                        isPrivateNetworkStall(refusal, session: session)
                    else { return declined(reason: refusal.message) }
                    networkStalled = true
                    continue
                }
            }
        }
    }

    // MARK: - Starting

    private static func start<C: Clock<Duration>>(
        session: any RunSession,
        settings: DaemonConfig.Snapshot,
        defaults: UserDefaults,
        waitForFirstAnswer: Duration,
        syncBudget: Duration?,
        questionBound: Duration,
        clock: C,
        now: @escaping @Sendable () -> Date,
        onProgress: @MainActor (ProgressUpdate) -> Void,
        watchProgress: @MainActor (ProgressUpdate) -> Void
    ) async throws(NodeAutomation.StartRefusal) -> NodeRunReport {
        // Privacy fails closed at the launch boundary — the one place this file
        // re-reads a live setting beside the snapshot. If the person turned Tor
        // *on* after the run entered (snapshot says off, live says on), starting
        // on a direct connection now would leak their home network address
        // moments after they asked for privacy. Turned *off* mid-flight, the
        // run declines instead: the preference write lands a step before the
        // screen tears the network down, so a still-reporting endpoint cannot
        // be trusted — `startArguments` declines the split before the proxy
        // floor is even checked. The decision itself lives in `NodeAutomation`
        // and is tested (ADR 0006).
        let liveEnabled = defaults.bool(forKey: "tor_enabled")
        let privacyEnabled = NodeAutomation.requiresPrivateNetwork(
            snapshotEnabled: settings.torEnabled,
            liveEnabled: liveEnabled)
        // `buildArguments` gates `-proxy=` on the snapshot's own tor flag, so it
        // is fed the effective one — a live-on tightening must actually put the
        // proxy in the arguments, not just pass the check below.
        var effectiveSettings = settings
        effectiveSettings.torEnabled = privacyEnabled
        let arguments: [String]
        do {
            arguments = try NodeAutomation.startArguments(
                snapshotEnabled: settings.torEnabled,
                liveEnabled: liveEnabled,
                // The address is offered only while the network is actually
                // usable: a Tor on its way down keeps reporting its old endpoint
                // until teardown finishes, so `proxyAddress` alone would bind
                // the node to a proxy that dies seconds after launch — and with
                // `-proxy=` set the daemon has no direct fallback, which makes a
                // dead launch reported as started strictly worse than a decline.
                proxyAddress: session.torIsReady ? session.torProxyAddress : nil,
                build: {
                    DaemonConfig.buildArguments(settings: effectiveSettings, torProxy: $0)
                })
        } catch let refusal {
            // The refusal exists because the shared argument builder simply omits
            // the proxy when no address is present, which unattended would start
            // the node on a direct connection. It is live rather than vestigial:
            // the device-condition read suspends on the first network report, and
            // the private network can drop — or be switched off — in that window,
            // after the step decision has already committed to starting. (While
            // that read could not suspend, the check genuinely was unreachable.)
            // `throws(StartRefusal)` lets the compiler prove this is the only
            // branch, and the verdict travels as typed data rather than being
            // re-derived from a second read.
            if refusal == .privateNetworkNotReady {
                // A stall, not a verdict — the `waitsForConnectivity` shape:
                // nothing has launched, so the transient drop routes back to
                // the decision loop, which owns the one grace — nudge, wait,
                // or the unchanged decline once the budget is spent. The
                // turned-off refusal stays a decline here: a preference the
                // person revoked is terminal, not something a wait can fix.
                log.notice(
                    "run: private network went not-ready inside the condition window — routing to the wait")
                throw refusal
            }
            log.error("run: refused to start — \(String(describing: refusal), privacy: .public)")
            return declined(reason: refusal.message)
        }

        // The height recorded before this run, so the report can say what arrived since
        // — which spans the minutes the node kept running after an earlier run ended.
        // Captured before the wait, not after: once the node reaches `.running` its
        // own sync poll begins overwriting the observational store the baseline
        // can still fall back to.
        let previous = lastRunBaseline(in: defaults)

        // The last checkpoint before the side effect: the condition read and the
        // argument build suspend nowhere, but a run cancelled in that window would
        // still launch the node it was called off to prevent.
        guard !Task.isCancelled else { return noAnswerReport() }

        // `start()` refuses anything but `.stopped`. Something else can have
        // moved the node off it while the device-condition read suspended —
        // another run, the app's own Start button, or a config change's
        // restart — and reporting `.started` then claims work this run did
        // not do, the exact distinction `waitForStarting` exists to keep.
        // Take that path instead: it waits on whoever's node is coming up and
        // reports what it finds honestly.
        guard session.startNode(
            arguments: arguments,
            torSession: privacyEnabled ? session.torSessionID : nil,
            torSocksPort: privacyEnabled ? session.torSocksPort : nil
        ) else {
            log.notice("run: node moved off stopped during the condition read — waiting on whoever started it")
            // The `.startNode` step's own condition read already ran —
            // nothing is owed again at the watch (FR-012).
            return await waitForStarting(
                session: session, within: waitForFirstAnswer,
                syncBudget: syncBudget, weighInOnEntry: false,
                questionBound: questionBound,
                clock: clock, now: now, defaults: defaults,
                onProgress: onProgress, watchProgress: watchProgress)
        }
        log.notice("run: node start requested")

        guard
            let reading = await awaitFirstAnswer(
                session: session, within: waitForFirstAnswer,
                questionBound: questionBound, clock: clock,
                onProgress: onProgress)
        else {
            // The wait can also end before its deadline: the run was cancelled, the
            // node was stopped from the app mid-wait, or an in-flight answer was
            // discarded because the world had already changed. Claiming "had not
            // come up yet" then would suggest the node is still on its way — it is
            // not. Same check `report()` runs, with the same report for a run that
            // got nothing it can stand behind.
            guard answerIsStillWanted(session: session) else {
                log.notice("run: wait ended early — run cancelled or node stopped")
                return noAnswerReport()
            }
            log.notice("run: node had not come up within the time available — left running")
            return didNotComeUpReport()
        }

        log.notice("run: node answered at block \(reading.height, privacy: .public)")
        if let syncBudget {
            // The `.startNode` step weighed conditions at preflight —
            // nothing is owed again at the watch (FR-012).
            return await watch(
                entry: reading, outcome: .started, previous: previous,
                weighInOnEntry: false,
                session: session, budget: syncBudget,
                questionBound: questionBound, clock: clock, now: now,
                onProgress: onProgress, watchProgress: watchProgress)
        }
        return await measuredReport(
            outcome: .started, previous: previous, reading: reading,
            questionBound: questionBound,
            session: session, clock: clock, onProgress: onProgress)
    }

    /// Waits on a node that is already coming up — started by an earlier run that
    /// ran out of time, or by the app itself — and reports what it finds.
    ///
    /// The wait is the same one a just-started node gets: `budget` bounds it and
    /// every question inside it is bounded by `questionBound`. An answer is
    /// reported `.alreadyRunning` rather than `.started` — this run did not start
    /// anything — and a wait that runs out is `.didNotComeUp`: "still starting"
    /// is literally true whoever started it.
    ///
    /// On a budgeted run the landing is different too: the entry gate decides
    /// whether the answer begins a watch rather than ending the run, and
    /// `watchProgress` carries the watch's own writes — band positions, not
    /// the stage fractions the wrapped `onProgress` maps. `weighInOnEntry`
    /// says whether the path that got here owes the entry weigh-in before
    /// the watch commits: the `.waitForStartingNode` step skipped preflight,
    /// while `start`'s fallback already weighed it.
    private static func waitForStarting<C: Clock<Duration>>(
        session: any RunSession,
        within budget: Duration,
        syncBudget: Duration?,
        weighInOnEntry: Bool,
        questionBound: Duration,
        clock: C,
        now: @escaping @Sendable () -> Date,
        defaults: UserDefaults,
        onProgress: @MainActor (ProgressUpdate) -> Void,
        watchProgress: @MainActor (ProgressUpdate) -> Void
    ) async -> NodeRunReport {
        // Captured before the wait for the same reason `start` captures it: once
        // the node reaches `.running` its own sync poll overwrites the
        // observational fallback the baseline can read.
        let previous = lastRunBaseline(in: defaults)
        guard
            let reading = await awaitFirstAnswer(
                session: session, within: budget,
                questionBound: questionBound, clock: clock,
                onProgress: onProgress)
        else {
            guard answerIsStillWanted(session: session) else {
                log.notice("run: wait ended early — run cancelled or node stopped")
                return noAnswerReport()
            }
            log.notice("run: node had not come up within the time available — left starting")
            return didNotComeUpReport()
        }
        log.notice("run: starting node answered at block \(reading.height, privacy: .public)")
        if let syncBudget {
            return await watch(
                entry: reading, outcome: .alreadyRunning, previous: previous,
                weighInOnEntry: weighInOnEntry,
                session: session, budget: syncBudget,
                questionBound: questionBound, clock: clock, now: now,
                onProgress: onProgress, watchProgress: watchProgress)
        }
        return await measuredReport(
            outcome: .alreadyRunning, previous: previous, reading: reading,
            questionBound: questionBound,
            session: session, clock: clock, onProgress: onProgress)
    }

    /// Asks the node one bounded question, logging the transport that will
    /// carry it — which is also the ceiling the answer's timing should be
    /// read against. `AutoTransport` picks per call inside the package:
    /// while the direct bridge is up, an answer is bounded by the bridge's
    /// ~30 s give-up (uncancellable — a timed-out call finishes in the
    /// background); over HTTP it rides `URLSession`'s ~60 s — the one
    /// transport `withHardTimeout`'s cancel genuinely terminates. The flag
    /// is consulted here, once per question, because a fast-starting node
    /// can flip it mid-run — and because the line is written before the
    /// question leaves, a question that never answers still leaves it,
    /// which is precisely the `noProgress` case the log exists for.
    ///
    /// - Returns: the answer, or `nil` when the bound elapsed or the call
    ///   was cancelled — the fold each call site spelled `try?` for.
    private static func ask<T: Sendable, C: Clock<Duration>>(
        _ question: String,
        session: any RunSession,
        within budget: Duration,
        clock: C,
        _ operation: @escaping @Sendable () async throws -> T
    ) async -> T? {
        let transport = session.bridgeReady
            ? "direct bridge (30 s ceiling)"
            : "http (60 s ceiling)"
        log.notice(
            "run: asking \(question, privacy: .public) via \(transport, privacy: .public)")
        return try? await withHardTimeout(budget, clock: clock, operation: operation)
    }

    /// Keeps asking the node whether it is up, giving up at the deadline.
    ///
    /// A `nil` here means only "no usable answer arrived" — the deadline may have
    /// expired, or the wait may have ended early because the run was cancelled, the
    /// node was stopped, or an answer landed after it was still wanted. Callers
    /// distinguish the cases with `answerIsStillWanted`, not by assuming a `nil`
    /// means the node is still coming up.
    ///
    /// Asks the node directly rather than watching the app's own "running" flag, which
    /// is set by a start-up loop that backs off to two-second gaps — up to two seconds
    /// of a short run would otherwise be spent with the node already up and nobody
    /// looking. Asking directly also yields the height without a second round trip.
    ///
    /// Each question is bounded by `withHardTimeout` at the smaller of the time
    /// remaining and `questionBound` — `questionBudget` on the short action's
    /// run, the wider `watchQuestionBudget` on a budgeted one, where a slow
    /// answer is the usual mid-IBD case rather than a dead node. The
    /// remaining-time half makes the deadline a hard one — a question cannot
    /// be called back once asked, so without its own bound the loop would
    /// sit inside it past the deadline and never notice. The ceiling half
    /// keeps one slow question from consuming a long wait whole: the iOS 27
    /// action waits minutes, and a question parked for all of them reports
    /// nothing in between.
    ///
    /// One deadline is computed up front rather than accumulating intervals, state is
    /// re-read every time rather than assumed (someone may open the app and stop the
    /// node mid-wait), and the sleep is interruptible so a stopped run exits promptly.
    private static func awaitFirstAnswer<C: Clock<Duration>>(
        session: any RunSession,
        within budget: Duration,
        questionBound: Duration,
        clock: C,
        onProgress: @MainActor (ProgressUpdate) -> Void
    ) async -> NodeAutomation.LiveReading? {
        let reader = session.reader
        let started = clock.now
        let deadline = started.advanced(by: budget)
        let budgetSeconds = Double(budget / .milliseconds(1)) / 1000

        while clock.now < deadline {
            if Task.isCancelled { return nil }
            if session.nodeState.isStoppedOrStopping { return nil }
            let remaining = clock.now.duration(to: deadline)
            let info = await ask(
                "getblockchaininfo", session: session,
                within: min(remaining, questionBound), clock: clock
            ) { try await reader.blockchainInfo() }
            if let info {
                // Re-read both facts now the answer is actually here, rather than
                // trusting the check at the top of this pass. A question already in
                // flight cannot be called back, so its answer can land after the run
                // was stopped or after someone opened the app and shut the node down.
                // Reporting it then would claim a success contradicting what they just
                // did. The decision itself lives in `NodeAutomation` and is tested.
                guard answerIsStillWanted(session: session) else { return nil }
                // Nine-tenths rather than full: the peer-count question still runs
                // after the answer lands, and the bar keeps a notch in reserve for
                // it — the milestones exist so movement corresponds to something
                // real. The wait loop below caps at the same mark so the bar never
                // steps backwards.
                onProgress(ProgressUpdate(fraction: 0.9))
                return NodeAutomation.reading(from: info)
            }
            let elapsed = Double(started.duration(to: clock.now) / .milliseconds(1)) / 1000
            onProgress(ProgressUpdate(
                fraction: budgetSeconds > 0 ? min(0.9, elapsed / budgetSeconds) : 0))
            // The nap is capped by the time left rather than fixed at half a
            // second: an uncapped sleep can outlive the deadline by most of its
            // length — a two-second wait was observed ending at ~2.2s — which
            // would make the deadline a soft one in the one place this loop
            // promises it is hard. For the same reason it takes no tolerance:
            // tolerance is *added* leeway the system may spend past the wake
            // it was asked for, so a ~1s slack here would let the sleep land
            // past the deadline the cap exists to honor. The run's shared
            // tolerance is for cadence sleeps like the heartbeat; this nap is
            // a deadline bound.
            let nap = min(
                .milliseconds(500), clock.now.duration(to: deadline))
            if nap > .zero {
                do { try await clock.sleep(for: nap) } catch { return nil }
            }
        }
        return nil
    }

    /// Whether a refusal escaping `start` is the transient stall the grace
    /// exists for — or a verdict to report.
    ///
    /// `start` throws only `.privateNetworkNotReady`; the typed-throws
    /// channel exists to route exactly that verdict back to the loop. But
    /// the signature cannot prove *which* refusal escaped, so the value is
    /// checked rather than assumed — and the value alone is not enough: a
    /// not-ready verdict landing while the network *still reports ready* is
    /// contradictory rather than transient (a proxy refused while usable is
    /// not something a wait can fix), so it fails the check too and keeps
    /// the terminal decline the loop's predecessor gave it — minus the
    /// nudge that decline used to fire: `tor.start()` on a network that
    /// reports ready short-circuits anyway, so nothing is lost with it.
    /// The re-read is advisory, not a second measurement: the refusal and
    /// this check run in one actor stretch, so the readiness seen here is
    /// the readiness the boundary refused on.
    private static func isPrivateNetworkStall(
        _ refusal: NodeAutomation.StartRefusal,
        session: any RunSession
    ) -> Bool {
        refusal == .privateNetworkNotReady && !session.torIsReady
    }

    /// Waits for the private network inside the grace, in this file's own
    /// loop shape — the deadline-and-nap poll `awaitFirstAnswer` runs, never
    /// a timeout wrapped around `TorViewModel.waitUntilReady`: that helper is
    /// a `@MainActor` loop whose `try?` sleep swallows cancellation, so an
    /// abandoned one keeps polling a display state nobody reads while the
    /// run reports over its head.
    ///
    /// The wait's premise is a stopped node that needs the network to start
    /// against, and its per-pass exits cover whatever can dissolve that
    /// premise or resolve the stall — the wait-predicate doctrine of
    /// re-checking the continuation's own preconditions:
    ///
    /// * the node left `.stopped` — started *or* stopped from the app, or by
    ///   another run. Every direction lands on the re-decision, and the
    ///   early exit is what makes a person's Stop un-overridable: a wait
    ///   that ran out its budget on a `.stopped` node the network just
    ///   readied for would relaunch the very node they stopped. The check
    ///   is a per-pass sample, not a transition record — a `.stopped` →
    ///   `.starting` → `.stopped` round trip inside one nap would be
    ///   invisible, and a real launch takes orders of magnitude longer
    ///   than 500 ms, so no round trip can complete inside one.
    /// * the network resolved either way — ready, or no longer able to
    ///   arrive inside what the wait has left: `torIsComingUp(within:)`
    ///   counts a scheduled retry as still coming only while it can land
    ///   inside the remaining budget — a torn-down or exhausted Tor, or
    ///   one whose next attempt is scheduled past the deadline, ends the
    ///   wait early instead of burning the budget on a network that
    ///   cannot arrive in time — and counts a restart queued behind a
    ///   teardown unconditionally, since teardowns are prompt.
    /// * the deadline — measured on the injected clock like every other
    ///   wait here.
    ///
    /// - Returns: `false` only when the run itself was cancelled — the one
    ///   exit that reports `noAnswer` rather than re-deciding.
    private static func awaitPrivateNetwork<C: Clock<Duration>>(
        session: any RunSession,
        within budget: Duration,
        clock: C,
        onProgress: @MainActor (ProgressUpdate) -> Void
    ) async -> Bool {
        let started = clock.now
        let deadline = started.advanced(by: budget)
        let budgetSeconds = Double(budget / .milliseconds(1)) / 1000

        while clock.now < deadline {
            if Task.isCancelled { return false }
            if session.nodeState != .stopped { return true }
            let remaining = clock.now.duration(to: deadline)
            if session.torIsReady || !session.torIsComingUp(within: remaining) {
                return true
            }
            let elapsed = Double(started.duration(to: clock.now) / .milliseconds(1)) / 1000
            // A raw stage fraction, like the first-answer ramp's writes:
            // the start-up band is applied where the caller hands this
            // wait its callback — this stage's own share of the bar once
            // the watch exists is the wrapper's job (FR-004), not a write's.
            onProgress(ProgressUpdate(
                fraction: budgetSeconds > 0 ? elapsed / budgetSeconds : 1))
            // The same deadline-capped nap the first-answer wait takes —
            // capped by the time left so the deadline stays hard, and no
            // tolerance: slack here is leeway the system may spend past the
            // deadline the cap exists to honor.
            let nap = min(
                .milliseconds(500), clock.now.duration(to: deadline))
            if nap > .zero {
                do { try await clock.sleep(for: nap) } catch { return false }
            }
        }
        return true
    }

    // MARK: - Reading

    /// Reads a node that is already up.
    ///
    /// Takes `onProgress` for the same reason the waiting loop does. This path used to
    /// report nothing at all, so an extended run spent the whole read showing an empty
    /// bar and then jumped to full — the exact shape the action was written to avoid.
    /// Each question is bounded by `questionBound` for the same reason the waiting
    /// loop's are: an unbounded one could be the only thing between the run and a
    /// thirty-second silence the system reads as a stall. The repeating nudge in the
    /// iOS 27 action is what guarantees the run keeps reporting; these milestones
    /// exist so the movement corresponds to something real rather than being pure
    /// invention.
    private static func report<C: Clock<Duration>>(
        session: any RunSession,
        syncBudget: Duration?,
        questionBound: Duration,
        clock: C,
        now: @escaping @Sendable () -> Date,
        defaults: UserDefaults,
        onProgress: @MainActor (ProgressUpdate) -> Void,
        watchProgress: @MainActor (ProgressUpdate) -> Void
    ) async -> NodeRunReport {
        let reader = session.reader
        onProgress(ProgressUpdate(fraction: 0.1))
        let info = await ask(
            "getblockchaininfo", session: session,
            within: questionBound, clock: clock
        ) { try await reader.blockchainInfo() }
        guard let info else {
            // It says it is running but will not answer — the anomaly most worth
            // a log line on an unattended run (daemon alive, RPC dead).
            log.notice("run: node claims to be running but did not answer")
            return noAnswerReport()
        }
        // The answer is real but may describe a world that no longer exists: the run
        // can have been cancelled, or the node stopped from the app, while the
        // question was in flight — and a question once asked cannot be called back.
        // The same re-check the waiting loop runs, with the same report for a
        // discarded answer: the run got nothing it can stand behind.
        guard answerIsStillWanted(session: session) else { return noAnswerReport() }
        onProgress(ProgressUpdate(fraction: 0.6))
        let previous = lastRunBaseline(in: defaults)
        let reading = NodeAutomation.reading(from: info)
        if let syncBudget {
            // Reached only from `.reportExistingNode`, which skipped
            // preflight — the weigh-in is owed (FR-012).
            return await watch(
                entry: reading, outcome: .alreadyRunning, previous: previous,
                weighInOnEntry: true,
                session: session, budget: syncBudget,
                questionBound: questionBound, clock: clock, now: now,
                onProgress: onProgress, watchProgress: watchProgress)
        }
        return await measuredReport(
            outcome: .alreadyRunning, previous: previous,
            reading: reading, questionBound: questionBound,
            session: session, clock: clock, onProgress: onProgress)
    }

    // MARK: - Watching

    /// The watch stage (FR-001, FR-005, FR-009, FR-018, FR-019): asks the
    /// node what it sees roughly every five seconds, on one absolute
    /// deadline, until something true ends the run — the node catches up,
    /// a leash trips, the budget is spent, or the node is stopped.
    ///
    /// `entry` is the live reading the landing path is already holding —
    /// the first answer on the waiting paths, the read itself on the
    /// already-running one — so the gate is consulted exactly once, here,
    /// on the reading that earned the consult. A decline reports the
    /// ending the gate carried and no watch runs; `.enter` admits the
    /// watch and nothing re-consults it — a mid-watch reading that would
    /// have declined at entry is judged by the pass's own `caughtUp`
    /// proof instead, ending `caughtUp` rather than `alreadyAtTip`.
    ///
    /// Between the gate's admission and the commit sits the weigh-in
    /// `weighInOnEntry` calls for (FR-012): the paths that skipped
    /// preflight — the already-running read and the wait on an
    /// already-starting node — owe T016's conditions check once before
    /// committing, where the start path already weighed it. A refusal
    /// ends `watchRefused` naming the condition — the node is already
    /// running, so the story is a refused consent, not a failed start —
    /// and no watch write lands. A node already stopped or stopping
    /// owes nothing and skips the gather; one that stops inside the
    /// network wait outranks the refusal that was about to be honored —
    /// the deliberate action beats the conditions verdict (FR-019), and
    /// the first pass ends it `nodeStopped`. The gather is charged to
    /// the run, not the budget: the deadline and the leash clock below
    /// both start past it, so at most ~2 s of entry work falls outside
    /// `syncBudget`.
    ///
    /// Every pass asks one question, sequential and bounded at
    /// `min(questionBound, remaining)` so the sync budget is a hard bound
    /// rather than soft by a whole question (the same shape
    /// `awaitFirstAnswer` already uses for its deadline). The pass then
    /// feeds `SyncWatchState` — an answer, a flat one, or `nil` — and
    /// applies `watchEnding` to candidacies computed from the pass's own
    /// facts: the stop flag, the pass's own catch-up proof, the state's
    /// leashes, the deadline. Cancellation is not a candidacy: it ends
    /// the run, never the watch, so it is checked at the top of the pass
    /// and again where an in-flight answer would be trusted — the same
    /// two-point rule the first-answer wait keeps, and deliberately
    /// separate from the node-stop flag.
    ///
    /// Two candidacies are constants for now: `conditionsChanged: false`
    /// and `peers: []` — T024's drift gather and T025's `getpeerinfo`
    /// ride-along fill them in. `watchEnding`'s signature is where they
    /// land, so a pass already reads like the finished shape.
    ///
    /// A fresh write lands on every pass: the run's liveness on the
    /// extended action, where the system ends a run that goes quiet. The
    /// write carries the watch band position of the distance closed —
    /// honest even when flat, since the same fraction rewritten claims
    /// the same position, not new progress — plus the card's detail line.
    /// The writes go to `watchProgress`, the raw callback: the wrap the
    /// caller hands `onProgress` maps stage fractions into the start-up
    /// band, and these positions are already band positions.
    ///
    /// The watch never touches the node — asking is all it does — and the
    /// report it ends on is the measured one, carrying the ending the
    /// watch earned and the heights gained since entry, from the last
    /// good reading: `nodeStopped` ends on it exactly like `caughtUp`.
    private static func watch<C: Clock<Duration>>(
        entry reading: NodeAutomation.LiveReading,
        outcome: NodeAutomation.Outcome,
        previous: NodeAutomation.TipBaseline?,
        weighInOnEntry: Bool,
        session: any RunSession,
        budget: Duration,
        questionBound: Duration,
        clock: C,
        now: @escaping @Sendable () -> Date,
        onProgress: @MainActor (ProgressUpdate) -> Void,
        watchProgress: @MainActor (ProgressUpdate) -> Void
    ) async -> NodeRunReport {
        let reader = session.reader
        switch NodeAutomation.watchEntry(reading: reading, now: now()) {
        case .decline(let result):
            // The gate's answer is the run's — no watch ran, and the
            // carried result (already at the tip, or a self-defined chain
            // that cannot claim one) collapses to the honest non-watch
            // ending.
            return await measuredReport(
                outcome: outcome, previous: previous, reading: reading,
                syncEnding: .init(collapsed: result),
                questionBound: questionBound,
                session: session, clock: clock, onProgress: onProgress)
        case .enter:
            break
        }
        // The weigh-in, when this path owes it: a dead node is never
        // gathered for — its stop outranks any verdict — and the flag is
        // re-read after the network wait because a stop landing inside
        // it outranks the refusal too; in both cases the first pass
        // below ends the run `nodeStopped` on the measured report. The
        // cancellation check is the same two-point rule the pass keeps.
        if weighInOnEntry, !session.nodeState.isStoppedOrStopping {
            let refusal = await weighIn(device: session.device, clock: clock)
            guard !Task.isCancelled else { return noAnswerReport() }
            if let refusal, !session.nodeState.isStoppedOrStopping {
                log.notice(
                    "run: entry weigh-in refused — \(String(describing: refusal), privacy: .public)")
                return await measuredReport(
                    outcome: outcome, previous: previous, reading: reading,
                    syncEnding: .watchRefused(refusal),
                    questionBound: questionBound,
                    session: session, clock: clock, onProgress: onProgress)
            }
        }

        var state = NodeAutomation.SyncWatchState(
            at: clock.now, entry: reading,
            lowPowerMode: session.device.lowPowerModeEnabled)
        var lastReading = reading
        let deadline = clock.now.advanced(by: budget)

        // The commit: the headline flips from "checking" to "syncing" and
        // the bar parks at the band floor — the fraction of distance
        // closed is zero by construction at entry — exactly where the
        // start-up writes left it.
        watchProgress(ProgressUpdate(
            fraction: NodeAutomation.watchBand(0),
            headline: NodeAutomation.watchingTitle,
            detail: NodeAutomation.watchDetail(
                height: reading.height, headers: reading.headers,
                silentFor: nil)))

        while true {
            if Task.isCancelled { return noAnswerReport() }
            var nodeStopped = session.nodeState.isStoppedOrStopping

            // One question per pass, sequential, capped by the time left.
            // A stopped node is never asked: the flag is the cheaper read
            // and the pass already holds its verdict.
            let remaining = clock.now.duration(to: deadline)
            var info: BlockchainInfo?
            if !nodeStopped, remaining > .zero {
                info = await ask(
                    "getblockchaininfo", session: session,
                    within: min(questionBound, remaining), clock: clock
                ) { try await reader.blockchainInfo() }
            }
            if Task.isCancelled { return noAnswerReport() }
            // The flag is re-read rather than trusted from the top of the
            // pass: a question already in flight cannot be called back,
            // so its answer can land after someone stopped the node — a
            // real answer describing a world that no longer exists.
            nodeStopped = session.nodeState.isStoppedOrStopping
            let freshReading = nodeStopped
                ? nil
                : info.map { NodeAutomation.reading(from: $0) }
            if let freshReading { lastReading = freshReading }

            state.advance(instant: clock.now, reading: freshReading)

            let ending = NodeAutomation.watchEnding(
                nodeStopped: nodeStopped,
                caughtUp: freshReading.map {
                    NodeAutomation.caughtUp(
                        reading: $0, headersAdvanced: state.headersAdvanced,
                        // T025's ride-along: qualifying flat passes will
                        // spend one `getpeerinfo` question; until then a
                        // pass carries no evidence.
                        peers: [], now: now())
                } ?? false,
                // T024's drift check lands here — no per-pass gather yet.
                conditionsChanged: false,
                noProgress: state.stall != nil,
                budgetSpent: clock.now.duration(to: deadline) <= .zero)

            // The liveness write — one per pass, ending or not. Fraction
            // and detail both come from the last good reading: a flat or
            // silent pass rewrites the same position honestly rather
            // than posing as earned progress.
            let silence = state.unproductive + state.flatWindow
            watchProgress(ProgressUpdate(
                fraction: NodeAutomation.watchBand(
                    NodeAutomation.syncFraction(
                        height: lastReading.height,
                        baselineHeight: state.baseline.height,
                        liveHeaders: lastReading.headers)),
                headline: NodeAutomation.watchingTitle,
                detail: NodeAutomation.watchDetail(
                    height: lastReading.height,
                    headers: lastReading.headers,
                    // Past the shorter leash the silence is worth a
                    // clause — the detail format renders minutes and
                    // hours, so anything smaller would churn on "0 min".
                    silentFor: silence >= state.unproductiveLeash
                        ? silence : nil)))

            guard let ending else {
                // Still watching: nap to the next pass, capped at the
                // budget so a sleep cannot outlive the deadline it is
                // waiting toward. The nap carries the run's shared
                // tolerance only while the budget can still absorb it —
                // tolerance is leeway spent *past* the requested wake,
                // so once the time left could no longer contain a
                // coalesced wake inside the deadline, the sleep asks for
                // none.
                let timeLeft = clock.now.duration(to: deadline)
                let nap = min(watchPollInterval, timeLeft)
                if nap > .zero {
                    do {
                        try await clock.sleep(
                            for: nap,
                            tolerance: timeLeft > watchPollInterval
                                + sleepTolerance
                                ? sleepTolerance : nil)
                    } catch { return noAnswerReport() }
                }
                continue
            }

            let syncEnding: NodeAutomation.SyncEnding
            switch ending {
            case .nodeStopped: syncEnding = .nodeStopped
            case .caughtUp: syncEnding = .caughtUp
            case .conditionsChanged:
                // Unreachable while the drift candidacy above is `false`
                // — T024 will feed it and name the refusal it found.
                syncEnding = .conditionsChanged(nil)
            case .noProgress:
                syncEnding = .noProgress(silentFor: silence)
            case .stillSyncing: syncEnding = .stillSyncing
            case .notMeasured:
                // `watchEnding` can never emit it — a committed watch
                // already holds an answer. The case maps only because the
                // switch must be exhaustive.
                syncEnding = .notMeasured
            }
            log.notice(
                "run: watch ended — \(String(describing: syncEnding), privacy: .public)")
            return await measuredReport(
                outcome: outcome, previous: previous, reading: lastReading,
                syncEnding: syncEnding,
                blocksGainedThisRun: NodeAutomation.blocksSince(
                    previous: state.baseline, to: lastReading),
                questionBound: questionBound,
                session: session, clock: clock, onProgress: onProgress)
        }
    }

    /// The report for a run holding a real reading: asks the last question
    /// (the peer count, bounded like every other), and fills the bar only once
    /// nothing is still outstanding.
    ///
    /// `previous` is captured by the caller before the wait it is about to
    /// do: the starting paths read it before `awaitFirstAnswer`, and
    /// `report` reads it once the node's answer is in — before the watch
    /// consumes it, so a watched run's delta still measures from before
    /// the run, not from inside it. It reads the run-owned `last_run_*`
    /// baseline — written only by a result that is actually returned — so the
    /// node's own sync poll (which writes the observational `last_known_*`
    /// every 30 seconds) can never collapse the delta toward zero just because
    /// the app was alive recently. Until any run has returned, the
    /// `last_known_*` fallback can already be seconds old, so a first-ever run
    /// against an already-running node can still report ≈0 — the pre-split
    /// behavior, self-correcting once a result lands. The delta itself is
    /// computed once and feeds both the named field and the sentence, so the
    /// two can never report different numbers.
    ///
    /// `syncEnding` and `blocksGainedThisRun` are the report's own data —
    /// `NodeRunReport.init` requires both — passed in rather than derived
    /// because the run that produced them already knows them: an
    /// unmeasured run has the defaults, a watched one the ending its
    /// watch earned and the gain its state measured. Behavior keys on the
    /// ending's *class* — the still-wanted rule below applies only while
    /// no measured ending exists — never on which ending arrived.
    ///
    /// Nothing is persisted here: the reading becomes a recorded tip only when
    /// the run's result is actually returned — a run cancelled or stopped
    /// between the last question and that return reports nothing, so it must
    /// not advance a baseline it never reported. The actions make that call
    /// at the shared result boundary: `resultUnlessCancelled` persists
    /// through `persistReportedTip(from:to:)` only when the report is
    /// actually returned.
    private static func measuredReport<C: Clock<Duration>>(
        outcome: NodeAutomation.Outcome,
        previous: NodeAutomation.TipBaseline?,
        reading: NodeAutomation.LiveReading,
        syncEnding: NodeAutomation.SyncEnding = .notMeasured,
        blocksGainedThisRun: Int? = nil,
        questionBound: Duration,
        session: any RunSession,
        clock: C,
        onProgress: @MainActor (ProgressUpdate) -> Void
    ) async -> NodeRunReport {
        let blocksSinceLastCheck = NodeAutomation.blocksSince(previous: previous, to: reading)
        // The peer question honors the watch's own rule: a node the watch
        // proved stopped is never asked — its answer could only be nil,
        // bought with up to `questionBound` spent against a dead bridge.
        // Every other ending still asks: its node was alive on the last
        // read, so the count may still be real.
        let connections = syncEnding == .nodeStopped
            ? nil
            : await connectionCount(
                session: session, within: questionBound, clock: clock)
        // The peer-count question above is another bounded wait — the same
        // window every path in this file re-checks after. Cancellation
        // blanks either kind of report — a cancelled run reports nothing.
        // A *stopped* node blanks only an unmeasured one: `nodeStopped` is
        // itself an ending a watch can earn and the measured report is what
        // carries it (FR-008), and the other watched endings are verdicts
        // the watch already holds, not readings a stop erases.
        let answerStillCounts = syncEnding.watched
            ? !Task.isCancelled
            : answerIsStillWanted(session: session)
        guard answerStillCounts else { return noAnswerReport() }
        onProgress(ProgressUpdate(fraction: 1))
        return NodeRunReport(
            outcome: NodeRunOutcome(outcome),
            syncEnding: syncEnding,
            chain: reading.chain,
            blockHeight: reading.height,
            blocksBehind: reading.blocksBehind,
            blocksSinceLastCheck: blocksSinceLastCheck,
            blocksGainedThisRun: blocksGainedThisRun,
            connections: connections,
            dialogTemplate: NodeAutomation.summary(
                outcome: outcome, syncEnding: syncEnding,
                chain: reading.chain, height: reading.height,
                blocksBehind: reading.blocksBehind, blocksSinceLastCheck: blocksSinceLastCheck,
                declinedReason: nil))
    }

    /// The report for a run that waited and the node never came up. The node is
    /// deliberately left running: it finishes coming up on its own thread and the
    /// next run sees the result. Asking a node still inside its own start-up to
    /// stop cannot be serviced and would hang until the system killed the run,
    /// which a person sees as a timeout.
    private static func didNotComeUpReport() -> NodeRunReport {
        return NodeRunReport(
            outcome: .didNotComeUp,
            syncEnding: .notMeasured,
            chain: nil,
            blockHeight: nil,
            blocksGainedThisRun: nil,
            dialogTemplate: NodeAutomation.summary(
                outcome: .didNotComeUp, syncEnding: .notMeasured,
                chain: "unknown", height: 0, blocksBehind: nil,
                blocksSinceLastCheck: nil, declinedReason: nil))
    }

    /// The report for a run that got no usable answer from the node — and carries no
    /// readings, because none were measured. Absent fields are how the report says
    /// "not measured"; a last-known figure beside that claim would contradict it.
    ///
    /// "No usable answer" covers a node that says it is running but never answered,
    /// and an answer that arrived only after the node was stopped or the run ended —
    /// real, but no longer describing the world, so it is discarded rather than
    /// reported.
    ///
    /// Not private — the iOS 27 action uses it as the answer of last resort when its
    /// own work ends without producing a report at all.
    static func noAnswerReport() -> NodeRunReport {
        return NodeRunReport(
            outcome: .noAnswer, syncEnding: .notMeasured,
            chain: nil, blockHeight: nil, blocksGainedThisRun: nil,
            dialogTemplate: NodeAutomation.summary(
                outcome: .noAnswer, syncEnding: .notMeasured,
                chain: "unknown", height: 0,
                blocksBehind: nil, blocksSinceLastCheck: nil,
                declinedReason: nil))
    }

    /// The node's peer count, or `nil` if it could not be asked. Absent rather than
    /// zero: a run that gained nothing because it never found a peer would otherwise
    /// look identical to one that had peers and still gained nothing.
    private static func connectionCount<C: Clock<Duration>>(
        session: any RunSession, within budget: Duration, clock: C
    ) async -> Int? {
        let reader = session.reader
        let info = await ask(
            "getnetworkinfo", session: session,
            within: budget, clock: clock
        ) { try await reader.networkInfo() }
        guard let info else { return nil }
        return info.connections
    }

    /// Reads the two facts `NodeAutomation.answerIsStillWanted` weighs, at the
    /// instant it is called — which is the point of the exercise, since both can
    /// change while a question is in flight. The decision stays in
    /// `NodeAutomation`; this only gathers what it decides on.
    private static func answerIsStillWanted(session: any RunSession) -> Bool {
        NodeAutomation.answerIsStillWanted(
            runWasCancelled: Task.isCancelled,
            nodeIsStopped: session.nodeState.isStoppedOrStopping)
    }

    /// The last tip a run actually reported, as a `TipBaseline` — the chain and
    /// height `blocksSince` measures against. Reads the run-owned baseline —
    /// the observational `last_known_*` the sync poll writes is a different
    /// store, so a run's delta is never truncated by background polling.
    ///
    /// A baseline keeps only the two facts a delta measures — the store
    /// remembers a third (when the tip was written) that `blocksSince` has no
    /// use for. It is not a `LiveReading`, so watch-only fields
    /// (`isInitialBlockDownload`, `headers`, `tipTime`) can never be read back
    /// as if they had been measured.
    ///
    /// The observational store is the fallback for the one case where no run
    /// baseline exists yet: the first run after the split was introduced (or
    /// a fresh install's first-ever run before any poll wrote — `nil` either
    /// way then). For it, `last_known_*` is still the last tip the person was
    /// ever shown, and measuring against it preserves the delta rather than
    /// dropping the sentence. Once any run returns a result, `last_run_*`
    /// exists and the fallback is never consulted again.
    ///
    /// A chain switch reads the same way: `last_run_*` still names the old
    /// chain, `blocksSince` refuses the cross-chain subtraction, and the
    /// first run on the new chain reports no delta rather than a nonsense
    /// one — then its returned result seeds the baseline going forward. The
    /// old single store behaved this way only by timing luck: it produced a
    /// figure only once a poll the person never saw had already overwritten
    /// the old-chain tip.
    private static func lastRunBaseline(
        in defaults: UserDefaults
    ) -> NodeAutomation.TipBaseline? {
        (NodeViewModel.lastRun(in: defaults) ?? NodeViewModel.lastKnown(in: defaults)).map {
            NodeAutomation.TipBaseline(chain: $0.chain, height: $0.height)
        }
    }

    /// Records the report's reading as both baselines it feeds: the run-owned
    /// `last_run_*` the next run's "blocks since last check" is measured from,
    /// and the observational `last_known_*` the dashboard's "last validated"
    /// line reads — a returned report is a legitimate observation too, though
    /// never a rewind: a same-chain `last_known_*` already ahead of the report
    /// (the poll can answer mid-question) survives.
    ///
    /// Called by the actions, not by the run itself, and only on the path that
    /// returns the report as a result. The report carries height and chain
    /// only when a measurement actually happened — a declined, unanswered, or
    /// discarded run has neither — so the guard is the whole contract: a run
    /// that reported no measurement cannot advance either baseline. Not
    /// private — `resultUnlessCancelled` calls it. The store is handed in
    /// rather than defaulted to `.standard`: a run-internal persist — the
    /// regression the result boundary exists against — spelled without a
    /// store would silently write the app's real settings, untouched by
    /// whatever a test handed the run.
    static func persistReportedTip(
        from report: NodeRunReport, to defaults: UserDefaults
    ) {
        guard let height = report.blockHeight, let chain = report.chain else { return }
        // `last_run_*` records exactly what this run reported — unconditional,
        // a reorg's lower tip included.
        NodeViewModel.persistLastRun(height: height, chain: chain, in: defaults)
        // The observational store may already hold a newer reading — the poll
        // can have written one while the run asked its last question. A
        // returned run must not rewind "last validated" past that: skip the
        // write when the stored tip is already ahead on the same chain. The
        // poll's unguarded writes keep reorgs and fresh heights converging on
        // their own cadence either way.
        if let known = NodeViewModel.lastKnown(in: defaults),
            known.chain == chain, known.height > height {
            return
        }
        NodeViewModel.persistLastKnown(height: height, chain: chain, in: defaults)
    }

    /// The result boundary both actions share: a report the run produced is
    /// returned and persisted only if it is still wanted at the instant it
    /// crosses back into the intent.
    ///
    /// Between the run's last "still wanted?" check and the `.result` return
    /// there is one more window where the answer can stop being wanted — the
    /// run can be cancelled in that span, or (for the iOS 27 action, which can
    /// also be told to stop) the person can end it. Returning then would
    /// deliver a result for a run the system has already forgotten — and
    /// `persistReportedTip` would advance `last_run_*` from an answer nobody
    /// was shown, collapsing the next run's "since last check" delta toward
    /// zero. The throw exists so the boundary can never persist what it did
    /// not return.
    ///
    /// `wasStopped` carries the long-running action's own stop signal — it is
    /// reported through a channel beside task cancellation, so it is weighed
    /// beside it rather than read as `Task.isCancelled`. The short action
    /// passes nothing.
    ///
    /// - Throws: `CancellationError` when the result is no longer wanted.
    ///
    /// `into` has no default for the same reason `persistReportedTip`'s store
    /// doesn't: a boundary call that forgot the store would silently persist
    /// to `.standard`, outside whatever a test handed the run.
    static func resultUnlessCancelled(
        _ report: NodeRunReport,
        wasStopped: Bool = false,
        into defaults: UserDefaults
    ) throws -> NodeRunReport {
        guard !wasStopped, !Task.isCancelled else {
            log.notice("run: cancelled — reporting the run as cancelled, not as a result")
            throw CancellationError()
        }
        persistReportedTip(from: report, to: defaults)
        return report
    }

    private static func declined(reason: LocalizedStringResource) -> NodeRunReport {
        return NodeRunReport(
            outcome: .declined,
            // A decline today has no sync answer to give; T016's weigh-in
            // refusal keeps the measured outcome and reports
            // `watchRefused` — it will bring its own.
            syncEnding: .notMeasured,
            chain: nil,
            blockHeight: nil,
            blocksGainedThisRun: nil,
            dialogTemplate: NodeAutomation.summary(
                outcome: .declined, syncEnding: .notMeasured,
                chain: "unknown", height: 0, blocksBehind: nil,
                blocksSinceLastCheck: nil, declinedReason: reason))
    }

    // MARK: - Device conditions

    /// The one wait in either conditions gather — the live network-cost
    /// report, bounded at two seconds, shared by `readConditions` and the
    /// entry weigh-in's `weighIn`. `first()`, not the watcher check
    /// `current` performs: a cold background launch means the watcher was
    /// just started, so `current` would read the default `.unknown`
    /// before the monitor's first fetch could land, and `unknown` passes
    /// the metered test — failing open exactly where consent matters
    /// most. Two seconds is long enough for a cold launch's report to
    /// arrive on the watcher and short enough that one that never comes
    /// falls back to the same not-known answer `current` would have
    /// given.
    private static func firstNetworkCost<C: Clock<Duration>>(
        device: any DeviceReadings,
        clock: C
    ) async -> NetworkCost {
        (try? await withHardTimeout(.seconds(2), clock: clock) {
            await device.networkFirst()
        }) ?? .unknown
    }

    /// Gathers the seven conditions `NodePreflight` weighs — the full set the
    /// start paths consult — out of the raw readings `device` exposes. The
    /// combination is the part worth testing, so it lives here rather than in
    /// the adapter: which readings, in what order, and how long the network
    /// answer may wait.
    ///
    /// Every reading is immediate except the network one, which this path
    /// waits on — briefly. The watcher started at launch normally has an
    /// answer ready, but on a background launch the run reaches this line
    /// within milliseconds of that start, before the first report has had
    /// time to land on the watcher's queue — and reading `networkCurrent`
    /// then would take "not yet reported" as "not costly", silently skipping
    /// the refusals that protect the person's data allowance. The wait is
    /// bounded: an earlier version suspended on the report unboundedly and
    /// could hang before the run ever reached the node, and a report that
    /// never comes falls back to the same not-known answer `networkCurrent`
    /// gives.
    private static func readConditions<C: Clock<Duration>>(
        device: any DeviceReadings,
        clock: C
    ) async -> NodePreflight.DeviceConditions {
        let network = await firstNetworkCost(device: device, clock: clock)
        let filesReadable = device.protectedDataAvailable
        // The folder prepare is a write, attempted only when files can be
        // read at all: before the first unlock after a restart it is doomed
        // to fail and would log a scary error on every such run — for a
        // refusal `filesNotReadable` already reports on its own. It also runs
        // before the disk read because free space is measured *on this
        // folder's volume*: until it exists the reading comes back unknown,
        // which the space check deliberately treats as "do not refuse". A
        // cancelled run skips the write — its conditions are discarded
        // either way.
        let chainFolderExists =
            filesReadable && !Task.isCancelled && device.prepareChainFolder()
        return NodePreflight.DeviceConditions(
            filesReadable: filesReadable,
            chainFolderExists: chainFolderExists,
            lowPowerModeEnabled: device.lowPowerModeEnabled,
            networkIsMetered: network.isMetered,
            networkIsDataRestricted: network.isDataRestricted,
            thermalState: device.thermalState,
            freeDiskBytes: device.freeDiskBytes()
        )
    }

    /// The gather T016's `entryWeighIn` weighs — the conditions a
    /// preflight-skipped path owes once before the watch commits
    /// (FR-012). Deliberately narrower than `readConditions`: a node
    /// answering RPCs has already proven its files readable and its
    /// chain folder present, so neither `protectedDataAvailable` nor
    /// `prepareChainFolder()` is consulted — no filesystem write belongs
    /// to a watch that never makes one.
    private static func weighIn<C: Clock<Duration>>(
        device: any DeviceReadings,
        clock: C
    ) async -> NodePreflight.Refusal? {
        let network = await firstNetworkCost(device: device, clock: clock)
        // A cancelled run discards whatever the verdict would have been —
        // skip the reads that remain rather than gather for nothing.
        guard !Task.isCancelled else { return nil }
        return NodeAutomation.entryWeighIn(
            lowPowerModeEnabled: device.lowPowerModeEnabled,
            networkIsMetered: network.isMetered,
            networkIsDataRestricted: network.isDataRestricted,
            thermalState: device.thermalState,
            freeDiskBytes: device.freeDiskBytes())
    }
}

#endif
