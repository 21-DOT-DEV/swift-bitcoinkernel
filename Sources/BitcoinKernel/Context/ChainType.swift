/// The Bitcoin network to configure a ``Context`` / ``ChainParameters``
/// for.
///
/// Each case maps to a distinct set of consensus rules defined in Bitcoin
/// Core's [`chainparams.cpp`](https://github.com/bitcoin/bitcoin/blob/master/src/kernel/chainparams.cpp):
/// genesis block, subsidy-halving interval, proof-of-work limits, soft-fork
/// activation heights, and (for signet) block-signing challenge.
///
/// Maps to the `btck_ChainType` constants in the kernel C API. The raw
/// values are stable and match `btck_CHAIN_TYPE_*`.
public enum ChainType: UInt8, Sendable, CaseIterable, Codable, CustomStringConvertible {
    /// Bitcoin production network — the real chain with real coins.
    ///
    /// Genesis at
    /// [`000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f`](https://mempool.space/block/000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f).
    /// Current tip storage requirement is ~600 GB and growing — not a
    /// practical target for mobile today.
    case mainnet  = 0

    /// Bitcoin testnet3 — the legacy public test network.
    ///
    /// Accumulated difficulty-reset-exploit anomalies over its long
    /// lifetime. Prefer ``testnet4`` for new test deployments.
    case testnet  = 1

    /// Bitcoin testnet4 — the current preferred public test network.
    ///
    /// Reset to avoid testnet3's accumulated difficulty anomalies and
    /// coinbase spam.
    case testnet4 = 2

    /// Bitcoin signet — challenge-signed blocks on a controlled test
    /// network per [BIP 325](https://github.com/bitcoin/bips/blob/master/bip-0325.mediawiki).
    ///
    /// Small (~50 MB at typical tip), predictable block rate, and immune to
    /// testnet-style difficulty games — the recommended real-network sync
    /// target for swift-bitcoinkernel.
    case signet   = 3

    /// Bitcoin regression test network — fully local, mineable-on-demand.
    ///
    /// No network peers, genesis-only by default, zero proof-of-work
    /// difficulty (any hash passes). Used by swift-bitcoinkernel's test suite via
    /// the `RegtestChainBuilder` test-support helper.
    case regtest  = 4

    /// The canonical lowercase name (`"mainnet"`, `"testnet"`, etc.),
    /// suitable for directory names and log output.
    public var description: String {
        switch self {
        case .mainnet:  return "mainnet"
        case .testnet:  return "testnet"
        case .testnet4: return "testnet4"
        case .signet:   return "signet"
        case .regtest:  return "regtest"
        }
    }
}
