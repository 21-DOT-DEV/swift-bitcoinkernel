/// A granular reason why a block was invalid.
///
/// Maps to `btck_BlockValidationResult` constants in the kernel C API.
public enum BlockValidationResult: UInt32, Sendable, CaseIterable, Codable, CustomStringConvertible {
    /// Block has not yet been rejected.
    case unset          = 0
    /// Invalid by consensus rules.
    case consensus      = 1
    /// Cached as invalid (reason not stored).
    case cachedInvalid  = 2
    /// Invalid proof of work or time too old.
    case invalidHeader  = 3
    /// Block data didn't match the PoW commitment.
    case mutated        = 4
    /// Previous block is missing.
    case missingPrev    = 5
    /// A block this one builds on is invalid.
    case invalidPrev    = 6
    /// Block timestamp was > 2 hours in the future.
    case timeFuture     = 7
    /// Block header may be on a too-little-work chain.
    case headerLowWork  = 8

    public var description: String {
        switch self {
        case .unset:         return "unset"
        case .consensus:     return "consensus"
        case .cachedInvalid: return "cached invalid"
        case .invalidHeader: return "invalid header"
        case .mutated:       return "mutated"
        case .missingPrev:   return "missing previous block"
        case .invalidPrev:   return "invalid previous block"
        case .timeFuture:    return "time too far in future"
        case .headerLowWork: return "header low work"
        }
    }
}
