/// The `BitcoinKernel` module provides idiomatic Swift types for the
/// `libbitcoinkernel` C API.
///
/// ## Quick Start
///
/// ```swift
/// import BitcoinKernel
///
/// let params = ChainParameters(.regtest)
/// let options = ContextOptions()
/// options.setChainParams(params)
/// let context = try Context(options: options)
/// ```
///
/// All types use Swift ARC for lifecycle management — no manual `destroy`
/// calls needed.
internal import libbitcoinkernel
