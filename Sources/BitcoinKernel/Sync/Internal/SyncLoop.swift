//
//  SyncLoop.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Placeholder remote tip used in the first ``BlockchainSync/Update`` emitted
/// before the real `bestTip()` response arrives. Zero height guarantees
/// `verificationProgress` reports `0.0`.
private let unknownRemoteTip = BlockTip(hash: Data(repeating: 0, count: 32), height: 0)

/// Resolve the local chainstate's current tip to a ``BlockTip`` value.
private func readLocalTip(_ manager: ChainstateManager) -> BlockTip {
    let entry = manager.bestEntry
    return BlockTip(
        hash: entry.blockHash.data,
        height: Int(entry.height),
        timestamp: Date(timeIntervalSince1970: TimeInterval(entry.blockHeader.timestamp))
    )
}

/// Sync driver — iterates through blocks from the source, processes each via
/// the chainstate manager, and emits ``BlockchainSync/Update`` values.
///
/// Structured for readability and testability (not for mainnet-scale
/// throughput). Runs inline on the caller's `Task`; inline processing
/// preserves block ordering and avoids the complexity of managing a
/// separate processing queue against the single-threaded kernel.
///
/// Termination:
/// - Happy path: emits `.finished` then `continuation.finish()`.
/// - Error path: emits `.failed(reason)` then `continuation.finish()`.
/// - Cancellation: detects `Task.isCancelled`, silently `continuation.finish()`es.
/// - In all cases, the caller's `onTermination` is responsible for calling
///   `context.interrupt()`.
@Sendable
func runSyncLoop(
    storage: SyncStorage,
    continuation: AsyncStream<BlockchainSync.Update>.Continuation
) async {
    var localTip = readLocalTip(storage.manager)

    // Emit initial .preparing. Remote is unknown at this point.
    continuation.yield(BlockchainSync.Update(
        state: .preparing,
        tip: localTip,
        remoteTip: unknownRemoteTip
    ))

    // Fetch remote tip.
    var remoteTip: BlockTip
    do {
        remoteTip = try await storage.source.bestTip()
    } catch is CancellationError {
        continuation.finish()
        return
    } catch {
        continuation.yield(BlockchainSync.Update(
            state: .failed(describeSyncFailure(error, at: "resolving remote tip")),
            tip: localTip,
            remoteTip: unknownRemoteTip
        ))
        continuation.finish()
        return
    }

    // Fork-point check (only when resuming from non-genesis local).
    if localTip.height > 0 {
        if remoteTip.height < localTip.height {
            continuation.yield(BlockchainSync.Update(
                state: .failed("remote is behind local (remote height \(remoteTip.height) < local height \(localTip.height))"),
                tip: localTip,
                remoteTip: remoteTip
            ))
            continuation.finish()
            return
        }
        do {
            let remoteHashAtLocalHeight = try await storage.source.blockHash(atHeight: localTip.height)
            if remoteHashAtLocalHeight != localTip.hash {
                continuation.yield(BlockchainSync.Update(
                    state: .failed("remote chain diverges at height \(localTip.height) — reindex required"),
                    tip: localTip,
                    remoteTip: remoteTip
                ))
                continuation.finish()
                return
            }
        } catch is CancellationError {
            continuation.finish()
            return
        } catch {
            continuation.yield(BlockchainSync.Update(
                state: .failed(describeSyncFailure(error, at: "fork-point check at height \(localTip.height)")),
                tip: localTip,
                remoteTip: remoteTip
            ))
            continuation.finish()
            return
        }
    }

    // Initialize Foundation.Progress with remote as totalUnitCount.
    storage.progress.totalUnitCount = Int64(remoteTip.height)
    storage.progress.completedUnitCount = Int64(localTip.height)

    // Main sync loop: fetch + process blocks one at a time.
    while true {
        if Task.isCancelled {
            continuation.finish()
            return
        }

        // Reached (or passed) current remoteTip — re-poll once to catch any
        // growth / reorg on the source.
        if localTip.height >= remoteTip.height {
            let freshRemote: BlockTip
            do {
                freshRemote = try await storage.source.bestTip()
            } catch is CancellationError {
                continuation.finish()
                return
            } catch {
                continuation.yield(BlockchainSync.Update(
                    state: .failed(describeSyncFailure(error, at: "re-checking remote tip at height \(localTip.height)")),
                    tip: localTip,
                    remoteTip: remoteTip
                ))
                continuation.finish()
                return
            }

            if freshRemote.height <= localTip.height {
                // Truly at tip — emit .finished and exit.
                continuation.yield(BlockchainSync.Update(
                    state: .finished,
                    tip: localTip,
                    remoteTip: freshRemote
                ))
                continuation.finish()
                return
            }

            // Remote advanced — update progress totalUnitCount and continue.
            remoteTip = freshRemote
            storage.progress.totalUnitCount = Int64(remoteTip.height)
        }

        let nextHeight = localTip.height + 1

        // Fetch next block.
        let block: Block
        do {
            let hash = try await storage.source.blockHash(atHeight: nextHeight)
            block = try await storage.source.block(for: hash)
        } catch is CancellationError {
            continuation.finish()
            return
        } catch {
            continuation.yield(BlockchainSync.Update(
                state: .failed(describeSyncFailure(error, at: "fetching block at height \(nextHeight)")),
                tip: localTip,
                remoteTip: remoteTip
            ))
            continuation.finish()
            return
        }

        // Validate + connect through the kernel.
        let (success, _) = storage.manager.processBlock(block)
        if !success {
            continuation.yield(BlockchainSync.Update(
                state: .failed("kernel rejected block at height \(nextHeight)"),
                tip: localTip,
                remoteTip: remoteTip
            ))
            continuation.finish()
            return
        }

        // Advance local tip from kernel's new best entry.
        localTip = readLocalTip(storage.manager)
        storage.progress.completedUnitCount = Int64(localTip.height)

        continuation.yield(BlockchainSync.Update(
            state: .syncing,
            tip: localTip,
            remoteTip: remoteTip
        ))
    }
}

/// Human-readable failure description for `.failed(String)` states.
private func describeSyncFailure(_ error: any Error, at context: String) -> String {
    if let localized = error as? LocalizedError, let msg = localized.errorDescription {
        return "\(context): \(msg)"
    }
    return "\(context): \(error)"
}
