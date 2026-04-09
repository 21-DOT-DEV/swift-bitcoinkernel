internal import libbitcoinkernel

/// Chain parameters describing the properties of a Bitcoin network.
///
/// Wraps the opaque `btck_ChainParameters` type. ARC via `deinit` calls
/// `btck_chain_parameters_destroy` when the last reference drops.
public final class ChainParameters: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Creates chain parameters for the given chain type.
    ///
    /// - Parameter chainType: The Bitcoin network to configure for.
    public init(_ chainType: ChainType) {
        self.pointer = btck_chain_parameters_create(chainType.rawValue)
    }

    deinit {
        btck_chain_parameters_destroy(pointer)
    }
}
