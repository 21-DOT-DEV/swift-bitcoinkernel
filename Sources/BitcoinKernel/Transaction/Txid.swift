internal import libbitcoinkernel
import Foundation

/// A 32-byte transaction identifier.
///
/// Wraps the opaque `btck_Txid` type. ARC via `deinit` calls
/// `btck_txid_destroy` when the last reference drops.
public final class Txid: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Internal initializer from an owned C pointer.
    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// The raw 32-byte txid data.
    public var data: Data {
        var output = [UInt8](repeating: 0, count: 32)
        output.withUnsafeMutableBufferPointer { buf in
            guard let baseAddress = buf.baseAddress else { return }
            btck_txid_to_bytes(pointer, baseAddress)
        }
        return Data(output)
    }

    /// Whether this txid equals another.
    public func equals(_ other: Txid) -> Bool {
        btck_txid_equals(pointer, other.pointer) != 0
    }

    deinit {
        btck_txid_destroy(pointer)
    }
}
