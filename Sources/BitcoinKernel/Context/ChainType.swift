/// The type of Bitcoin chain to use.
///
/// Maps to `btck_ChainType` constants in the kernel C API.
public enum ChainType: UInt8, Sendable {
    /// Bitcoin production network.
    case mainnet  = 0
    /// Bitcoin testnet3 (deprecated).
    case testnet  = 1
    /// Bitcoin testnet4.
    case testnet4 = 2
    /// Bitcoin signet (uses challenge-based block signing).
    case signet   = 3
    /// Bitcoin regression test network for local development.
    case regtest  = 4
}
