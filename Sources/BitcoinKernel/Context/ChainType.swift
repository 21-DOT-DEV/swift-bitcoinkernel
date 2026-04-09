/// The type of Bitcoin chain to use.
///
/// Maps to `btck_ChainType` constants in the kernel C API.
public enum ChainType: UInt8, Sendable {
    case mainnet  = 0
    case testnet  = 1
    case testnet4 = 2
    case signet   = 3
    case regtest  = 4
}
