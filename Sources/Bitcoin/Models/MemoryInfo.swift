//
//  MemoryInfo.swift
//  21-DOT-DEV/swift-bitcoin
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

/// Memory usage information from `getmemoryinfo` (mode "stats").
///
/// - Note: Targets Bitcoin Core v31.x. The "mallocinfo" mode returns raw XML
///   and is not modeled here — use `RPCClient.call()` for that case.
public struct MemoryInfo: Codable, Sendable, Equatable {
    /// Information about the locked memory manager.
    public let locked: LockedMemory
}

/// Locked memory manager statistics.
public struct LockedMemory: Codable, Sendable, Equatable {
    /// Number of bytes used.
    public let used: Int

    /// Number of bytes available in current arenas.
    public let free: Int

    /// Total number of bytes managed.
    public let total: Int

    /// Amount of bytes that succeeded locking.
    ///
    /// If this number is smaller than `total`, locking pages failed at
    /// some point and key data could be swapped to disk.
    public let locked: Int

    /// Number of allocated chunks.
    public let chunksUsed: Int

    /// Number of unused chunks.
    public let chunksFree: Int

    enum CodingKeys: String, CodingKey {
        case used, free, total, locked
        case chunksUsed = "chunks_used"
        case chunksFree = "chunks_free"
    }
}
