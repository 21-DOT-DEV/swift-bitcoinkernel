//
//  BlockHash.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2024-2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

internal import libbitcoinkernel
import Foundation

/// A 32-byte block hash (double-SHA256 of the block header).
///
/// Wraps the opaque `btck_BlockHash` type. ARC via `deinit` calls
/// `btck_block_hash_destroy` when the last reference drops.
public final class BlockHash: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Creates a block hash from raw 32-byte data.
    ///
    /// - Parameter data: Exactly 32 bytes of hash data.
    /// - Precondition: `data.count == 32`.
    public init(_ data: Data) {
        precondition(data.count == 32, "BlockHash requires exactly 32 bytes")
        self.pointer = data.withUnsafeBytes { rawBuf in
            guard let baseAddress = rawBuf.baseAddress else {
                preconditionFailure("BlockHash requires exactly 32 bytes")
            }
            return btck_block_hash_create(baseAddress.assumingMemoryBound(to: UInt8.self))
        }
    }

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The raw 32-byte hash data.
    public var data: Data {
        var output = [UInt8](repeating: 0, count: 32)
        output.withUnsafeMutableBufferPointer { buf in
            guard let baseAddress = buf.baseAddress else { return }
            btck_block_hash_to_bytes(pointer, baseAddress)
        }
        return Data(output)
    }

    /// Whether this block hash equals another.
    public func equals(_ other: BlockHash) -> Bool {
        btck_block_hash_equals(pointer, other.pointer) != 0
    }

    deinit {
        btck_block_hash_destroy(pointer)
    }
}

// MARK: - Swift-value ergonomics
//
// `BlockHash` is a reference type (it owns a `btck_BlockHash` C pointer),
// but semantically it represents a 32-byte hash value. These conformances
// let it be used like any other Swift value — compared with `==`, stored
// in `Set`/`Dictionary`, constructed via `RawRepresentable`, and printed
// as human-readable display-order hex.

extension BlockHash: Equatable {
    /// Two block hashes are equal iff their 32 raw bytes are identical.
    /// Delegates to the C-side `btck_block_hash_equals` for the canonical
    /// comparison.
    public static func == (lhs: BlockHash, rhs: BlockHash) -> Bool {
        lhs.equals(rhs)
    }
}

extension BlockHash: Hashable {
    /// Hashes the 32 raw bytes. Consistent with `Equatable`: equal hashes
    /// produce equal hash values.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.data)
    }
}

extension BlockHash: RawRepresentable {
    public typealias RawValue = Data

    /// The 32-byte raw hash data in internal (kernel) byte order.
    public var rawValue: Data { self.data }

    /// Creates a ``BlockHash`` from raw bytes, returning `nil` if the input
    /// is not exactly 32 bytes.
    ///
    /// - Parameter rawValue: Raw hash data in internal byte order.
    public convenience init?(rawValue: Data) {
        guard rawValue.count == 32 else { return nil }
        self.init(rawValue)
    }
}

extension BlockHash: CustomStringConvertible {
    /// 64-character lowercase hex string in **display order** — the same
    /// convention Bitcoin block explorers use. Note that `data` returns the
    /// bytes in **internal (kernel) order** (reversed from display). For
    /// example, the mainnet genesis block's display hash is
    /// `000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f`.
    public var description: String {
        Data(self.data.reversed()).map { String(format: "%02x", $0) }.joined()
    }
}
