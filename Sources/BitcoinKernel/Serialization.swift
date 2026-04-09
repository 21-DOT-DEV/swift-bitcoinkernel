internal import libbitcoinkernel
import Foundation

/// Collects bytes from a kernel serialization function into `Data`.
///
/// - Parameter body: A closure that calls the C serialization function,
///   passing the provided writer callback and user data pointer.
///   Returns 0 on success.
/// - Returns: The serialized bytes, or `nil` if serialization failed.
func serializeToData(
    _ body: (btck_WriteBytes, UnsafeMutableRawPointer) -> Int32
) -> Data? {
    var data = Data()
    let result = withUnsafeMutablePointer(to: &data) { dataPtr in
        body(
            { bytes, size, userData in
                guard let bytes, let userData else { return 1 }
                let ptr = userData.assumingMemoryBound(to: Data.self)
                ptr.pointee.append(
                    UnsafePointer<UInt8>(OpaquePointer(bytes)),
                    count: size
                )
                return 0
            },
            UnsafeMutableRawPointer(dataPtr)
        )
    }
    return result == 0 ? data : nil
}
