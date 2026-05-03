import Testing
import BitcoinKernel
import Foundation

// MARK: - BlockchainSync.Update.State (terminal / equality)

@Test func updateStatePreparingIsNotTerminal() {
    #expect(!BlockchainSync.Update.State.preparing.isTerminal)
}

@Test func updateStateSyncingIsNotTerminal() {
    #expect(!BlockchainSync.Update.State.syncing.isTerminal)
}

@Test func updateStateFinishedIsTerminal() {
    #expect(BlockchainSync.Update.State.finished.isTerminal)
}

@Test func updateStateFailedIsTerminal() {
    #expect(BlockchainSync.Update.State.failed("anything").isTerminal)
}

@Test func updateStateEqualityAcrossCases() {
    #expect(BlockchainSync.Update.State.preparing != .syncing)
    #expect(BlockchainSync.Update.State.syncing != .finished)
    #expect(BlockchainSync.Update.State.finished != .failed(""))
}

@Test func updateStateFailedEqualityUsesReason() {
    #expect(BlockchainSync.Update.State.failed("a") == .failed("a"))
    #expect(BlockchainSync.Update.State.failed("a") != .failed("b"))
}

// MARK: - BlockchainSync.Update (equality + field storage)

private let localHash = Data(repeating: 0, count: 32)
private let remoteHash = Data(repeating: 0xAA, count: 32)

@Test func updateEqualityWithIdenticalFields() {
    let tip = BlockTip(hash: localHash, height: 5)
    let remoteTip = BlockTip(hash: remoteHash, height: 10)
    let a = BlockchainSync.Update(state: .syncing, tip: tip, remoteTip: remoteTip)
    let b = BlockchainSync.Update(state: .syncing, tip: tip, remoteTip: remoteTip)
    #expect(a == b)
}

@Test func updateInequalityOnDifferentStates() {
    let tip = BlockTip(hash: localHash, height: 5)
    let remoteTip = BlockTip(hash: remoteHash, height: 10)
    let a = BlockchainSync.Update(state: .syncing, tip: tip, remoteTip: remoteTip)
    let b = BlockchainSync.Update(state: .finished, tip: tip, remoteTip: remoteTip)
    #expect(a != b)
}

@Test func updateInequalityOnDifferentLocalTipHeight() {
    let remoteTip = BlockTip(hash: remoteHash, height: 10)
    let a = BlockchainSync.Update(
        state: .syncing,
        tip: BlockTip(hash: localHash, height: 4),
        remoteTip: remoteTip
    )
    let b = BlockchainSync.Update(
        state: .syncing,
        tip: BlockTip(hash: localHash, height: 5),
        remoteTip: remoteTip
    )
    #expect(a != b)
}

// MARK: - verificationProgress computation

@Test func updateVerificationProgressAtHalfway() {
    let update = BlockchainSync.Update(
        state: .syncing,
        tip: BlockTip(hash: localHash, height: 5),
        remoteTip: BlockTip(hash: remoteHash, height: 10)
    )
    #expect(update.verificationProgress == 0.5)
}

@Test func updateVerificationProgressAtZero() {
    let update = BlockchainSync.Update(
        state: .preparing,
        tip: BlockTip(hash: localHash, height: 0),
        remoteTip: BlockTip(hash: remoteHash, height: 10)
    )
    #expect(update.verificationProgress == 0.0)
}

@Test func updateVerificationProgressAtOne() {
    let update = BlockchainSync.Update(
        state: .finished,
        tip: BlockTip(hash: localHash, height: 10),
        remoteTip: BlockTip(hash: remoteHash, height: 10)
    )
    #expect(update.verificationProgress == 1.0)
}

@Test func updateVerificationProgressClampsWhenLocalAheadOfRemote() {
    // Transient reorg edge case: local temporarily exceeds remote.
    let update = BlockchainSync.Update(
        state: .syncing,
        tip: BlockTip(hash: localHash, height: 15),
        remoteTip: BlockTip(hash: remoteHash, height: 10)
    )
    #expect(update.verificationProgress == 1.0)
}

@Test func updateVerificationProgressIsZeroWhenRemoteUnknown() {
    // Before the first bestTip() response, remote is effectively unknown (height 0).
    let update = BlockchainSync.Update(
        state: .preparing,
        tip: BlockTip(hash: localHash, height: 0),
        remoteTip: BlockTip(hash: remoteHash, height: 0)
    )
    #expect(update.verificationProgress == 0.0)
}

// MARK: - Sendable compile check

@Test func updateTypesAreSendable() {
    func requireSendable<T: Sendable>(_ value: T) {}
    requireSendable(BlockchainSync.Update.State.preparing)
    requireSendable(BlockchainSync.Update(
        state: .preparing,
        tip: BlockTip(hash: localHash, height: 0),
        remoteTip: BlockTip(hash: remoteHash, height: 0)
    ))
}
